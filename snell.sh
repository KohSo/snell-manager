#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_VERSION="1.1.0"
OFFICIAL_BASE="https://dl.nssurge.com/snell"
MANAGED_ETC="/etc/snell-instances"
MANAGED_LIB="/usr/local/lib/snell"
SYSTEMD_DIR="/etc/systemd/system"
SYSTEMCTL_BIN="${SNELL_SYSTEMCTL:-systemctl}"
SS_BIN="${SNELL_SS:-ss}"

V5_VERSION="5.0.1"
V6_PACKAGE_VERSION="6.0.0rc"
V5_AMD64_SHA256="5b2e221f2c6e29b1db8e47053e1221be29d5627da807cb932b089f514a3609f0"
V6_AMD64_SHA256="02fa15ac1e18cde6a3e072eeb5d15328c7fd759dbefb1e77e33891a71a1202ae"

GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
RESET='\033[0m'
MENU_RULE='=============================='
MENU_DIVIDER='——————————————————————————————'

declare -a INST_UNIT=() INST_BIN=() INST_CONF=() INST_VERSION=() INST_MAJOR=()
declare -a INST_PORT=() INST_LISTEN=() INST_ACTIVE=() INST_ENABLED=() INST_MANAGED=()

info() { printf "%b[信息]%b %s\n" "$GREEN" "$RESET" "$*"; }
warn() { printf "%b[提示]%b %s\n" "$YELLOW" "$RESET" "$*" >&2; }
die() { printf "%b[错误]%b %s\n" "$RED" "$RESET" "$*" >&2; exit 1; }

require_root() {
  [[ ${EUID:-$(id -u)} -eq 0 ]] || die "请使用 root 或 sudo 运行。"
}

require_supported_system() {
  [[ -r /etc/os-release ]] || die "无法识别操作系统。"
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" ]] || die "v1.0 仅正式支持 Debian 12/13。"
  [[ "${VERSION_ID:-}" == "12" || "${VERSION_ID:-}" == "13" ]] || \
    die "v1.0 仅正式支持 Debian 12/13，当前为 ${PRETTY_NAME:-unknown}。"
  [[ $(uname -m) == "x86_64" ]] || die "v1.0 仅正式支持 x86_64。"
  command -v "$SYSTEMCTL_BIN" >/dev/null || die "未找到 systemctl。"
  command -v "$SS_BIN" >/dev/null || die "未找到 ss。"
}

trim() {
  local value=${1-}
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

config_value() {
  local file=$1 key=$2
  awk -v wanted="$key" '
    /^[[:space:]]*#/ { next }
    {
      line=$0
      pos=index(line,"=")
      if (!pos) next
      k=substr(line,1,pos-1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      if (k==wanted) {
        v=substr(line,pos+1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        print v
        exit
      }
    }
  ' "$file" 2>/dev/null || true
}

extract_port() {
  local listen=$1 first
  first=${listen%%,*}
  if [[ $first =~ :([0-9]+)$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

replace_listen_port() {
  local listen=$1 port=$2 part out=""
  IFS=',' read -r -a parts <<< "$listen"
  for part in "${parts[@]}"; do
    part=$(trim "$part")
    part=$(sed -E "s/:[0-9]+$/:${port}/" <<< "$part")
    [[ -n $out ]] && out+=","
    out+="$part"
  done
  printf '%s' "$out"
}

binary_version() {
  local bin=$1 output
  [[ -x $bin ]] || return 0
  output=$($bin --version 2>&1 || true)
  sed -nE 's/.*snell-server v([0-9]+([.][0-9A-Za-z]+)*).*/\1/p' <<< "$output" | head -n1
}

major_from_version() {
  local version=$1
  [[ $version =~ ^([0-9]+) ]] && printf '%s' "${BASH_REMATCH[1]}"
}

unit_exec_line() {
  "$SYSTEMCTL_BIN" cat "$1" 2>/dev/null | awk -F= '/^[[:space:]]*ExecStart=/ { line=substr($0,index($0,"=")+1) } END { print line }'
}

parse_exec_line() {
  local line=$1 token previous="" bin="" conf=""
  read -r -a tokens <<< "$line"
  for token in "${tokens[@]}"; do
    token=${token#\"}; token=${token%\"}
    if [[ -z $bin && $token == /* ]]; then bin=$token; fi
    if [[ $previous == "-c" ]]; then conf=$token; break; fi
    previous=$token
  done
  printf '%s\t%s\n' "$bin" "$conf"
}

add_instance() {
  local unit=$1 bin=$2 conf=$3 key version major listen port active enabled managed i
  [[ -n $bin && -n $conf && -f $conf ]] || return 0
  key="$bin|$conf"
  for i in "${!INST_BIN[@]}"; do
    [[ "${INST_BIN[$i]}|${INST_CONF[$i]}" == "$key" ]] && return 0
  done
  version=$(binary_version "$bin")
  [[ -n $version ]] || version=$(config_value "$conf" version)
  major=$(major_from_version "$version")
  [[ $major == 5 || $major == 6 ]] || return 0
  listen=$(config_value "$conf" listen)
  port=$(extract_port "$listen")
  active=$($SYSTEMCTL_BIN is-active "$unit" 2>/dev/null || true)
  enabled=$($SYSTEMCTL_BIN is-enabled "$unit" 2>/dev/null || true)
  managed=no
  [[ $conf == "$MANAGED_ETC"/* ]] && managed=yes
  INST_UNIT+=("$unit"); INST_BIN+=("$bin"); INST_CONF+=("$conf")
  INST_VERSION+=("$version"); INST_MAJOR+=("$major"); INST_PORT+=("$port")
  INST_LISTEN+=("$listen"); INST_ACTIVE+=("$active"); INST_ENABLED+=("$enabled")
  INST_MANAGED+=("$managed")
}

discover_instances() {
  INST_UNIT=(); INST_BIN=(); INST_CONF=(); INST_VERSION=(); INST_MAJOR=()
  INST_PORT=(); INST_LISTEN=(); INST_ACTIVE=(); INST_ENABLED=(); INST_MANAGED=()
  local unit line parsed bin conf
  mapfile -t units < <(
    {
      "$SYSTEMCTL_BIN" list-units --type=service --state=running --no-legend --plain 2>/dev/null || true
      "$SYSTEMCTL_BIN" list-unit-files --type=service --no-legend 2>/dev/null || true
    } | awk 'tolower($1) ~ /snell/ {print $1}' | awk '!seen[$0]++'
  )
  for unit in "${units[@]}"; do
    line=$(unit_exec_line "$unit")
    [[ $line == *snell-server* ]] || continue
    parsed=$(parse_exec_line "$line")
    bin=${parsed%%$'\t'*}; conf=${parsed#*$'\t'}
    add_instance "$unit" "$bin" "$conf"
  done
}

state_word() {
  [[ $1 == active ]] && printf "%b运行中%b" "$GREEN" "$RESET" || printf "%b已停止%b" "$RED" "$RESET"
}

print_instances() {
  local i
  printf '\n%-4s %-23s %-9s %-9s %-8s %-10s %s\n' "编号" "服务" "版本" "端口" "托管" "状态" "配置"
  printf '%s\n' "------------------------------------------------------------------------------------------------"
  for i in "${!INST_UNIT[@]}"; do
    printf '%-4s %-23s %-9s %-9s %-8s %-20b %s\n' "$((i+1))" "${INST_UNIT[$i]}" \
      "v${INST_VERSION[$i]}" "${INST_PORT[$i]:--}" "${INST_MANAGED[$i]}" \
      "$(state_word "${INST_ACTIVE[$i]}")" "${INST_CONF[$i]}"
  done
  ((${#INST_UNIT[@]})) || warn "未发现 Snell v5/v6 systemd 实例。"
}

redacted_config() {
  sed -E 's/^([[:space:]]*psk[[:space:]]*=[[:space:]]*).*/\1[REDACTED]/I' "$1"
}

audit() {
  discover_instances
  printf 'Snell Manager v%s 只读审计\n' "$SCRIPT_VERSION"
  # shellcheck disable=SC1091
  printf '主机: %s | 系统: %s | 架构: %s\n' "$(hostname)" "$(. /etc/os-release; printf '%s %s' "$ID" "$VERSION_ID")" "$(uname -m)"
  print_instances
  local i proto
  for i in "${!INST_UNIT[@]}"; do
    printf '\n[%s] 配置（PSK 已遮盖）\n' "${INST_UNIT[$i]}"
    redacted_config "${INST_CONF[$i]}"
    printf '监听核验:\n'
    "$SS_BIN" -lntup 2>/dev/null | awk -v p=":${INST_PORT[$i]}" 'index($0,p) {print}' || true
    proto=tcp
    [[ ${INST_MAJOR[$i]} == 5 ]] && proto="tcp+udp"
    printf '预期传输: %s\n' "$proto"
  done
}

public_ipv4() {
  local ip="" url
  if command -v curl >/dev/null; then
    for url in https://api.ipify.org https://api.ip.sb/ip https://ifconfig.co/ip; do
      ip=$(curl -4fsS --max-time 4 "$url" 2>/dev/null | tr -d '[:space:]' || true)
      [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && break
      ip=""
    done
  elif command -v wget >/dev/null; then
    for url in https://api.ipify.org https://api.ip.sb/ip https://ifconfig.co/ip; do
      ip=$(wget -4qO- -T 4 "$url" 2>/dev/null | tr -d '[:space:]' || true)
      [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && break
      ip=""
    done
  fi
  printf '%s' "$ip"
}

yes_no_value() {
  local value=$1 default=${2:-false}
  if [[ -z $value ]]; then
    printf '%s' "$default"
  elif [[ $value =~ ^[Yy]$ ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

surge_endpoint() {
  local endpoint=$1
  if [[ $endpoint == *:* && $endpoint != \[*\] ]]; then
    printf '[%s]' "$endpoint"
  else
    printf '%s' "$endpoint"
  fi
}

build_surge_line() {
  local name=$1 endpoint=$2 port=$3 psk=$4 version=$5 mode=$6 obfs=$7 obfs_host=$8
  local client_tfo=$9 client_ecn=${10} reuse=${11:-false} line
  line="$name = snell, $(surge_endpoint "$endpoint"), $port, psk=$psk, version=$version"
  if [[ $version == 6 && -n $mode ]]; then
    line+=", mode=$mode"
  elif [[ $version == 4 && $obfs == http ]]; then
    line+=", obfs=http"
    [[ -n $obfs_host ]] && line+=", obfs-host=$obfs_host"
  fi
  line+=", tfo=$client_tfo"
  [[ $reuse == true ]] && line+=", reuse=true"
  line+=", ecn=$client_ecn"
  printf '%s' "$line"
}

print_surge_configs() {
  local i=$1 endpoint=$2 name=$3 client_tfo=$4 client_ecn=$5
  local psk mode obfs obfs_host
  psk=$(config_value "${INST_CONF[$i]}" psk)
  mode=$(config_value "${INST_CONF[$i]}" mode)
  obfs=$(config_value "${INST_CONF[$i]}" obfs)
  obfs_host=$(config_value "${INST_CONF[$i]}" obfs-host)
  printf '\nSurge 客户端配置：\n'
  if [[ ${INST_MAJOR[$i]} == 5 ]]; then
    printf '# v5 原生\n%s\n' "$(build_surge_line "$name-v5" "$endpoint" "${INST_PORT[$i]}" "$psk" 5 "" "" "" "$client_tfo" "$client_ecn" true)"
    printf '\n# v4 兼容（连接复用）\n%s\n' "$(build_surge_line "$name-v4" "$endpoint" "${INST_PORT[$i]}" "$psk" 4 "" "$obfs" "$obfs_host" "$client_tfo" "$client_ecn" true)"
  else
    printf '%s\n' "$(build_surge_line "$name" "$endpoint" "${INST_PORT[$i]}" "$psk" 6 "${mode:-default}" "" "" "$client_tfo" "$client_ecn" true)"
  fi
}

print_default_surge_configs() {
  local i=$1 endpoint server_tfo
  endpoint=$(public_ipv4)
  if [[ -z $endpoint ]]; then
    warn "无法获取公网 IPv4；请稍后从实例菜单生成 Surge 配置并手动输入地址。"
    return 0
  fi
  server_tfo=$(config_value "${INST_CONF[$i]}" tfo)
  [[ $server_tfo == true || $server_tfo == false ]] || server_tfo=true
  print_surge_configs "$i" "$endpoint" "$(hostname)" "$server_tfo" true
  printf '\n默认沿用 xOS 偏好：客户端 TFO=%s、ECN=true；可从实例菜单重新生成。\n' "$server_tfo"
}

summary_surge_line() {
  local i=$1 endpoint=$2 name=$3 psk tfo mode obfs obfs_host line
  psk=$(config_value "${INST_CONF[$i]}" psk)
  [[ -n $endpoint && -n ${INST_PORT[$i]} && -n $psk ]] || return 1
  tfo=$(config_value "${INST_CONF[$i]}" tfo)
  mode=$(config_value "${INST_CONF[$i]}" mode)
  obfs=$(config_value "${INST_CONF[$i]}" obfs)
  obfs_host=$(config_value "${INST_CONF[$i]}" obfs-host)
  line="$name = snell, $(surge_endpoint "$endpoint"), ${INST_PORT[$i]}, psk=$psk, version=${INST_MAJOR[$i]}"
  [[ ${INST_MAJOR[$i]} != 6 ]] || line+=", mode=${mode:-default}"
  if [[ ${INST_MAJOR[$i]} == 5 && $obfs == http ]]; then
    line+=", obfs=http"
    [[ -n $obfs_host ]] && line+=", obfs-host=$obfs_host"
  fi
  line+=", reuse=true"
  if [[ $tfo == true || $tfo == false ]]; then
    line+=", tfo=$tfo, ecn=true"
  fi
  printf '%s' "$line"
}

view_current_configs() {
  discover_instances
  local endpoint name base i count=${#INST_UNIT[@]}
  ((count)) || { warn "未发现 Snell v5/v6 实例。"; return; }
  endpoint=$(public_ipv4)
  [[ -n $endpoint ]] || { warn "无法获取公网 IPv4，暂时不能生成 Surge 配置。"; return; }
  base=$(hostname)
  printf '\n当前 Surge 配置：\n\n'
  for i in "${!INST_UNIT[@]}"; do
    name=$base
    ((count == 1)) || name="$base v${INST_MAJOR[$i]}"
    summary_surge_line "$i" "$endpoint" "$name" || warn "${INST_UNIT[$i]} 缺少端口或 PSK，无法生成。"
    printf '\n'
  done
}

view_instance() {
  local i=$1
  printf '\nSnell 实例配置：\n'
  printf '服务: %s\n二进制: %s\n配置: %s\n状态: %s / %s\n' \
    "${INST_UNIT[$i]}" "${INST_BIN[$i]}" "${INST_CONF[$i]}" \
    "${INST_ACTIVE[$i]}" "${INST_ENABLED[$i]}"
  printf '%s\n' "------------------------------------------------------------"
  cat "${INST_CONF[$i]}"
  printf '%s\n' "------------------------------------------------------------"
}

port_free() {
  local port=$1 ignore=${2:-}
  [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]] || return 1
  [[ $port == "$ignore" ]] && return 0
  ! "$SS_BIN" -H -lntup 2>/dev/null | awk -v p=":$port" '$5 ~ p"$" {found=1} END{exit !found}'
}

random_port() {
  local candidate
  for _ in $(seq 1 200); do
    candidate=$((10000 + 0x$(od -An -N2 -tx2 /dev/urandom | tr -d ' ') % 50001))
    if port_free "$candidate"; then printf '%s' "$candidate"; return 0; fi
  done
  return 1
}

random_psk() {
  local major=${1:-5} length=16 value
  [[ $major != 6 ]] || length=20
  value=$(set +o pipefail; LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c "$length")
  [[ ${#value} == "$length" ]] || return 1
  printf '%s' "$value"
}

write_key_to_temp() {
  local source=$1 dest=$2 key=$3 value=$4
  awk -v wanted="$key" -v replacement="$value" '
    BEGIN {done=0}
    {
      line=$0; pos=index(line,"=")
      if ($0 !~ /^[[:space:]]*#/ && pos) {
        k=substr(line,1,pos-1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
        if (k==wanted) {print wanted " = " replacement; done=1; next}
      }
      print
    }
    END {if (!done) print wanted " = " replacement}
  ' "$source" > "$dest"
}

apply_config_change() {
  local i=$1 key=$2 value=$3 conf unit tmp backup stamp
  conf=${INST_CONF[$i]}; unit=${INST_UNIT[$i]}
  stamp=$(date +%Y%m%d-%H%M%S)
  backup="${conf}.backup-${stamp}"
  tmp=$(mktemp "${conf}.tmp.XXXXXX")
  write_key_to_temp "$conf" "$tmp" "$key" "$value"
  chmod --reference="$conf" "$tmp" 2>/dev/null || chmod 600 "$tmp"
  cp -a "$conf" "$backup"
  mv "$tmp" "$conf"
  if "$SYSTEMCTL_BIN" restart "$unit" && "$SYSTEMCTL_BIN" is-active --quiet "$unit"; then
    info "配置已更新；备份为 $backup"
    return 0
  fi
  warn "新配置启动失败，正在恢复。"
  cp -a "$backup" "$conf"
  "$SYSTEMCTL_BIN" restart "$unit" || true
  "$SYSTEMCTL_BIN" is-active --quiet "$unit" || die "回滚后服务仍未恢复，请检查 $unit。"
  die "已回滚本次配置修改。"
}

edit_instance() {
  local i=$1 choice key value port current display_value psk
  psk=$(config_value "${INST_CONF[$i]}" psk)
  printf '\n当前配置摘要\n端口: %s\nPSK: [已设置，%s 位]\nTFO: %s\nDNS: %s\n出口接口: %s\n' \
    "${INST_PORT[$i]:--}" "${#psk}" "$(config_value "${INST_CONF[$i]}" tfo)" \
    "$(config_value "${INST_CONF[$i]}" dns)" "$(config_value "${INST_CONF[$i]}" egress-interface)"
  if [[ ${INST_MAJOR[$i]} == 5 ]]; then
    printf 'IPv6 目标解析: %s\nOBFS: %s\nOBFS Host: %s\n' \
      "$(config_value "${INST_CONF[$i]}" ipv6)" "$(config_value "${INST_CONF[$i]}" obfs)" \
      "$(config_value "${INST_CONF[$i]}" obfs-host)"
  else
    printf 'DNS IP 偏好: %s\nmode: %s\nlisten: %s\n' \
      "$(config_value "${INST_CONF[$i]}" dns-ip-preference)" "$(config_value "${INST_CONF[$i]}" mode)" \
      "${INST_LISTEN[$i]}"
  fi
  printf '\n1. 端口\n2. PSK\n3. TFO\n4. DNS\n5. 出口接口\n'
  if [[ ${INST_MAJOR[$i]} == 5 ]]; then
    printf '6. IPv6 解析\n7. OBFS\n8. OBFS Host\n'
  else
    printf '6. DNS IP 偏好\n7. mode\n8. listen（完整值）\n'
  fi
  read -r -p "选择配置项: " choice
  case "$choice" in
    1)
      read -r -p "新端口: " port
      current=${INST_PORT[$i]}
      port_free "$port" "$current" || die "端口无效或已被占用。"
      key=listen; value=$(replace_listen_port "${INST_LISTEN[$i]}" "$port")
      ;;
    2)
      key=psk; read -r -p "新 PSK（留空按 xOS 默认随机生成）: " value; [[ -n $value ]] || value=$(random_psk "${INST_MAJOR[$i]}")
      if [[ ${INST_MAJOR[$i]} == 6 ]]; then
        [[ ${#value} -ge 16 && ${#value} -le 255 ]] || die "v6 PSK 必须为 16–255 位。"
      else
        [[ ${#value} -ge 12 && ${#value} -le 255 ]] || die "v5 PSK 必须为 12–255 位。"
      fi
      ;;
    3) key=tfo; read -r -p "true/false: " value; [[ $value == true || $value == false ]] || die "只能输入 true 或 false。" ;;
    4) key=dns; read -r -p "DNS（逗号分隔）: " value; [[ -n $value ]] || die "DNS 不能为空。" ;;
    5) key=egress-interface; read -r -p "出口接口: " value; [[ -n $value ]] || die "出口接口不能为空。" ;;
    6)
      if [[ ${INST_MAJOR[$i]} == 5 ]]; then
        key=ipv6; read -r -p "true/false: " value; [[ $value == true || $value == false ]] || die "只能输入 true 或 false。"
      else
        key=dns-ip-preference; read -r -p "default/prefer-ipv4/prefer-ipv6/ipv4-only/ipv6-only: " value
        [[ $value =~ ^(default|prefer-ipv4|prefer-ipv6|ipv4-only|ipv6-only)$ ]] || die "无效值。"
      fi
      ;;
    7)
      if [[ ${INST_MAJOR[$i]} == 5 ]]; then
        key=obfs; read -r -p "off/http: " value; [[ $value == off || $value == http ]] || die "无效值。"
      else
        key=mode; read -r -p "default/unshaped/unsafe-raw: " value
        [[ $value =~ ^(default|unshaped|unsafe-raw)$ ]] || die "无效值。"
        [[ $value != unsafe-raw ]] || { read -r -p "unsafe-raw 为明文，仅输入 UNSAFE 确认: " choice; [[ $choice == UNSAFE ]] || die "已取消。"; }
      fi
      ;;
    8)
      if [[ ${INST_MAJOR[$i]} == 5 ]]; then key=obfs-host; else key=listen; fi
      read -r -p "新值: " value; [[ -n $value ]] || die "值不能为空。"
      if [[ $key == listen ]]; then
        port=$(extract_port "$value")
        [[ -n $port ]] || die "listen 必须包含端口。"
        while IFS= read -r current; do
          [[ $(extract_port "$current") == "$port" ]] || die "v1.0 要求多个监听地址使用同一端口。"
        done < <(tr ',' '\n' <<< "$value")
        port_free "$port" "${INST_PORT[$i]}" || die "listen 端口已被占用。"
      fi
      ;;
    *) die "无效选项。" ;;
  esac
  display_value=$value
  [[ $key != psk ]] || display_value="[已设置，${#value} 位]"
  printf '将修改 %s: %s = %s\n' "${INST_UNIT[$i]}" "$key" "$display_value"
  read -r -p "确认并重启该实例？[y/N]: " choice
  [[ $choice =~ ^[Yy]$ ]] || { info "已取消。"; return; }
  apply_config_change "$i" "$key" "$value"
}

download_official() {
  local major=$1 dest=$2 version url expected archive extracted actual
  command -v unzip >/dev/null || die "缺少 unzip，请先安装：apt-get install unzip"
  if [[ $major == 5 ]]; then
    version=$V5_VERSION; expected=$V5_AMD64_SHA256
  else
    version=$V6_PACKAGE_VERSION; expected=$V6_AMD64_SHA256
  fi
  url="$OFFICIAL_BASE/snell-server-v${version}-linux-amd64.zip"
  archive="$dest/package.zip"; extracted="$dest/extracted"
  mkdir -p "$extracted"
  if command -v curl >/dev/null; then
    curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$archive"
  elif command -v wget >/dev/null; then
    wget -qO "$archive" "$url"
  else
    die "缺少 curl 或 wget。"
  fi
  unzip -q "$archive" -d "$extracted"
  [[ -f $extracted/snell-server ]] || die "官方压缩包中未找到 snell-server。"
  actual=$(sha256sum "$extracted/snell-server" | awk '{print $1}')
  [[ $actual == "$expected" ]] || die "SHA-256 不匹配，拒绝安装。"
  install -m 0755 "$extracted/snell-server" "$dest/snell-server"
}

firewall_offer() {
  local major=$1 port=$2 answer
  if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q '^Status: active'; then
    read -r -p "UFW 已启用，放行 $port/tcp$([[ $major == 5 ]] && printf ' 和 udp')？[Y/n]: " answer
    [[ -n $answer ]] || answer=y
    if [[ $answer =~ ^[Yy]$ ]]; then ufw allow "$port/tcp"; [[ $major == 5 ]] && ufw allow "$port/udp"; fi
  elif command -v firewall-cmd >/dev/null && firewall-cmd --state 2>/dev/null | grep -q running; then
    read -r -p "firewalld 已启用，放行新端口？[Y/n]: " answer
    [[ -n $answer ]] || answer=y
    if [[ $answer =~ ^[Yy]$ ]]; then
      firewall-cmd --permanent --add-port="$port/tcp"
      [[ $major == 5 ]] && firewall-cmd --permanent --add-port="$port/udp"
      firewall-cmd --reload
    fi
  else
    info "未检测到启用的 UFW/firewalld；未修改防火墙。"
  fi
}

write_server_config() {
  local dest=$1 major=$2 port=$3 psk=$4 server_tfo=$5 dns=$6
  local ipv6=${7:-false} obfs=${8:-off} obfs_host=${9:-}
  local dns_ip_pref=${10:-default} mode=${11:-default}
  if [[ $major == 5 ]]; then
    printf '%s\n' '[snell-server]' "listen = 0.0.0.0:$port" "psk = $psk" \
      "ipv6 = $ipv6" "obfs = $obfs" > "$dest"
    [[ $obfs != http ]] || printf 'obfs-host = %s\n' "$obfs_host" >> "$dest"
    printf '%s\n' "tfo = $server_tfo" "dns = $dns" 'version = 5' >> "$dest"
  else
    printf '%s\n' '[snell-server]' "listen = 0.0.0.0:$port,[::]:$port" "psk = $psk" \
      "tfo = $server_tfo" "dns = $dns" \
      "dns-ip-preference = $dns_ip_pref" "mode = $mode" 'version = 6' > "$dest"
  fi
}

deploy_major() {
  local major=$1
  local unit="snell-v${major}.service" etcdir="$MANAGED_ETC/v${major}"
  local libdir="$MANAGED_LIB/v${major}"
  local conf="$etcdir/config.conf" bin="$libdir/snell-server"
  local unitfile="$SYSTEMD_DIR/$unit" port psk choice stage committed=0
  local server_tfo=true dns='1.1.1.1, 8.8.8.8, 2001:4860:4860::8888'
  local ipv6=false obfs=off obfs_host="" dns_ip_pref=default mode=default
  local i
  for i in "${!INST_MAJOR[@]}"; do [[ ${INST_MAJOR[$i]} != "$major" ]] || die "已存在 v$major 实例：${INST_UNIT[$i]}"; done
  [[ ! -e $unitfile && ! -e $etcdir && ! -e $libdir ]] || die "目标路径已存在，拒绝覆盖：v$major"
  port=2345
  if ! port_free "$port"; then
    port=$(random_port) || die "默认端口 2345 已占用，且未能找到其他空闲端口。"
    warn "xOS 默认端口 2345 已占用，本次改用空闲端口 $port。"
  fi
  read -r -p "监听端口（默认 $port）: " choice; [[ -z $choice ]] || port=$choice
  port_free "$port" || die "端口无效或已被占用。"
  psk=$(random_psk "$major") || die "未能生成随机 PSK。"
  read -r -p "PSK（留空按 xOS 默认生成：v5 16位 / v6 20位）: " choice; [[ -z $choice ]] || psk=$choice
  [[ ${#psk} -ge 16 && ${#psk} -le 255 ]] || die "PSK 必须为 16–255 位。"

  read -r -p "服务端启用 TCP Fast Open？[Y/n]: " choice
  [[ ! $choice =~ ^[Nn]$ ]] || server_tfo=false
  read -r -p "DNS（默认 $dns）: " choice; [[ -z $choice ]] || dns=$choice
  [[ -n $dns ]] || die "DNS 不能为空。"
  if [[ $major == 5 ]]; then
    read -r -p "允许解析并连接 IPv6 目标？[y/N]: " choice
    ipv6=$(yes_no_value "$choice")
    read -r -p "OBFS（默认 off，可输入 http）: " choice
    [[ -z $choice ]] || obfs=$choice
    [[ $obfs == off || $obfs == http ]] || die "OBFS 只能是 off 或 http。"
    if [[ $obfs == http ]]; then
      read -r -p "OBFS Host（必填）: " obfs_host
      [[ -n $obfs_host ]] || die "启用 HTTP OBFS 时 Host 不能为空。"
    fi
  else
    read -r -p "DNS IP 偏好（默认 default）: " choice
    [[ -z $choice ]] || dns_ip_pref=$choice
    [[ $dns_ip_pref =~ ^(default|prefer-ipv4|prefer-ipv6|ipv4-only|ipv6-only)$ ]] || die "无效 DNS IP 偏好。"
    read -r -p "v6 mode（默认 default，可选 unshaped/unsafe-raw）: " choice
    [[ -z $choice ]] || mode=$choice
    [[ $mode =~ ^(default|unshaped|unsafe-raw)$ ]] || die "无效 mode。"
    if [[ $mode == unsafe-raw ]]; then
      read -r -p "unsafe-raw 不加密，输入 UNSAFE 确认: " choice
      [[ $choice == UNSAFE ]] || die "已取消 unsafe-raw 部署。"
    fi
  fi

  printf '\n部署摘要（不会修改现有实例）\n'
  printf '版本: v%s\n服务: %s\n监听端口: %s\nPSK: [已设置，%s 位]\n服务端 TFO: %s\nDNS: %s\n' \
    "$major" "$unit" "$port" "${#psk}" "$server_tfo" "$dns"
  if [[ $major == 5 ]]; then
    printf 'IPv6 目标解析: %s\nOBFS: %s\n' "$ipv6" "$obfs"
    [[ $obfs == http ]] && printf 'OBFS Host: %s\n' "$obfs_host"
  else
    printf 'DNS IP 偏好: %s\nmode: %s\n' "$dns_ip_pref" "$mode"
  fi
  read -r -p "确认部署？[y/N]: " choice
  [[ $choice =~ ^[Yy]$ ]] || { info "已取消。"; return; }
  stage=$(mktemp -d /tmp/snell-manager.XXXXXX)
  cleanup_deploy() {
    local rc=$?
    rm -f "$stage/package.zip" "$stage/snell-server" "$stage/extracted/snell-server" 2>/dev/null || true
    rmdir "$stage/extracted" "$stage" 2>/dev/null || true
    if [[ $rc -ne 0 && $committed -eq 0 ]]; then
      "$SYSTEMCTL_BIN" disable --now "$unit" >/dev/null 2>&1 || true
      rm -f "$unitfile" "$conf" "$bin" 2>/dev/null || true
      rmdir "$etcdir" "$libdir" 2>/dev/null || true
      "$SYSTEMCTL_BIN" daemon-reload >/dev/null 2>&1 || true
    fi
    trap - RETURN EXIT
    return "$rc"
  }
  trap cleanup_deploy RETURN EXIT
  download_official "$major" "$stage"
  install -d -m 0700 "$etcdir"
  install -d -m 0755 "$libdir"
  install -m 0755 "$stage/snell-server" "$bin"
  umask 077
  write_server_config "$conf" "$major" "$port" "$psk" "$server_tfo" "$dns" \
    "$ipv6" "$obfs" "$obfs_host" "$dns_ip_pref" "$mode"
  chmod 600 "$conf"
  umask 022
  printf '%s\n' '[Unit]' "Description=Snell v$major managed instance" \
    'After=network-online.target' 'Wants=network-online.target' '' '[Service]' \
    'Type=simple' 'User=root' 'LimitNOFILE=32768' \
    "ExecStart=$bin -c $conf" 'Restart=on-failure' 'RestartSec=5s' '' '[Install]' \
    'WantedBy=multi-user.target' > "$unitfile"
  chmod 644 "$unitfile"
  "$SYSTEMCTL_BIN" daemon-reload
  "$SYSTEMCTL_BIN" enable --now "$unit"
  sleep 1
  "$SYSTEMCTL_BIN" is-active --quiet "$unit" || { "$SYSTEMCTL_BIN" status "$unit" --no-pager || true; return 1; }
  "$SS_BIN" -H -lnt 2>/dev/null | grep -q ":$port " || die "未发现 $port/TCP 监听。"
  if [[ $major == 5 ]]; then "$SS_BIN" -H -lnu 2>/dev/null | grep -q ":$port " || die "未发现 $port/UDP 监听。"; fi
  committed=1
  firewall_offer "$major" "$port"
  info "v$major 已部署并设为开机启动。"
  printf 'PSK: %s\n' "$psk"
  discover_instances
  for i in "${!INST_UNIT[@]}"; do
    if [[ ${INST_UNIT[$i]} == "$unit" ]]; then
      print_default_surge_configs "$i"
      break
    fi
  done
}

update_instance() {
  local i=$1 major=${INST_MAJOR[$1]} bin=${INST_BIN[$1]} unit=${INST_UNIT[$1]}
  local stage backup choice expected_version current
  current=${INST_VERSION[$i]}
  expected_version=$([[ $major == 5 ]] && printf '%s' "$V5_VERSION" || printf '%s' "$V6_PACKAGE_VERSION")
  printf '当前 v%s；目标官方包 %s。将只更新 %s。\n' "$current" "$expected_version" "$unit"
  read -r -p "继续？[y/N]: " choice
  [[ $choice =~ ^[Yy]$ ]] || return 0
  stage=$(mktemp -d /tmp/snell-manager-update.XXXXXX)
  download_official "$major" "$stage"
  backup="${bin}.backup-$(date +%Y%m%d-%H%M%S)"
  cp -a "$bin" "$backup"
  install -m 0755 "$stage/snell-server" "$bin"
  if "$SYSTEMCTL_BIN" restart "$unit" && "$SYSTEMCTL_BIN" is-active --quiet "$unit"; then
    info "更新成功；旧二进制保留为 $backup"
  else
    warn "更新失败，恢复旧二进制。"
    cp -a "$backup" "$bin"
    "$SYSTEMCTL_BIN" restart "$unit" || true
    die "更新已回滚。"
  fi
}

remove_managed_instance() {
  local i=$1 confirm unit conf bin
  [[ ${INST_MANAGED[$i]} == yes ]] || { warn "旧实例只原地管理，不允许脚本删除。"; return 1; }
  unit=${INST_UNIT[$i]}; conf=${INST_CONF[$i]}; bin=${INST_BIN[$i]}
  read -r -p "输入服务名 $unit 确认卸载: " confirm
  [[ $confirm == "$unit" ]] || { warn "确认不匹配，已取消。"; return 1; }
  "$SYSTEMCTL_BIN" disable --now "$unit"
  rm -f "$SYSTEMD_DIR/$unit" "$conf" "$bin"
  rmdir "${conf%/*}" "${bin%/*}" 2>/dev/null || true
  "$SYSTEMCTL_BIN" daemon-reload
  info "已删除脚本托管实例 $unit；该操作不恢复防火墙规则。"
  discover_instances
}

find_major_instance() {
  local major=$1 i
  MAJOR_INDEX=""
  for i in "${!INST_MAJOR[@]}"; do
    if [[ ${INST_MAJOR[$i]} == "$major" ]]; then
      MAJOR_INDEX=$i
      return 0
    fi
  done
  return 1
}

print_major_status() {
  local major=$1 i=""
  find_major_instance "$major" && i=$MAJOR_INDEX
  if [[ -z $i ]]; then
    printf '%b未安装%b' "$RED" "$RESET"
  elif [[ ${INST_ACTIVE[$i]} == active ]]; then
    printf '%b已安装%b%b[v%s]%b且%b已启动%b' \
      "$GREEN" "$RESET" "$YELLOW" "$major" "$RESET" "$GREEN" "$RESET"
  else
    printf '%b已安装%b%b[v%s]%b但%b未启动%b' \
      "$GREEN" "$RESET" "$YELLOW" "$major" "$RESET" "$RED" "$RESET"
  fi
}

print_main_status() {
  local i5="" i6=""
  find_major_instance 5 && i5=$MAJOR_INDEX
  find_major_instance 6 && i6=$MAJOR_INDEX
  if [[ -z $i5 && -z $i6 ]]; then
    printf '%b未安装 Snell v5/v6%b' "$RED" "$RESET"
  elif [[ -n $i5 && -n $i6 && ${INST_ACTIVE[$i5]} == active && ${INST_ACTIVE[$i6]} == active ]]; then
    printf '%b已安装%b%b[v5]%b & %b[v6]%b且%b已启动%b' \
      "$GREEN" "$RESET" "$YELLOW" "$RESET" "$YELLOW" "$RESET" "$GREEN" "$RESET"
  else
    printf 'v5: '
    print_major_status 5
    printf ' | v6: '
    print_major_status 6
  fi
}

major_menu() {
  local major=$1 choice i
  while true; do
    discover_instances
    i=""
    find_major_instance "$major" && i=$MAJOR_INDEX
    printf '\n%s\nSnell v%s 管理\n%s\n' "$MENU_RULE" "$major" "$MENU_RULE"
    printf '1.安装 Snell v%s\n2.卸载 Snell v%s\n3.更新 当前配置\n' "$major" "$major"
    printf '%s\n' "$MENU_DIVIDER"
    printf '4.启动 Snell v%s\n5.停止 Snell v%s\n6.重启 Snell v%s\n' "$major" "$major" "$major"
    printf '%s\n' "$MENU_DIVIDER"
    printf '7.设置 配置信息\n8.查看 配置信息\n9.查看 运行状态\n'
    printf '%s\n 00. 返回\n%s\n\n' "$MENU_DIVIDER" "$MENU_RULE"
    printf ' 当前状态: '
    print_major_status "$major"
    printf '\n\n'
    read -r -p " 请输入数字[0-9]:" choice
    case "$choice" in
      1)
        if [[ -n $i ]]; then warn "Snell v$major 已安装：${INST_UNIT[$i]}"; else deploy_major "$major"; fi
        ;;
      2)
        if [[ -n $i ]]; then remove_managed_instance "$i" || true; else warn "Snell v$major 尚未安装。"; fi
        ;;
      3)
        if [[ -n $i ]]; then update_instance "$i"; else warn "Snell v$major 尚未安装。"; fi
        ;;
      4)
        if [[ -n $i ]]; then "$SYSTEMCTL_BIN" start "${INST_UNIT[$i]}" && info "Snell v$major 已启动。"; else warn "Snell v$major 尚未安装。"; fi
        ;;
      5)
        if [[ -n $i ]]; then "$SYSTEMCTL_BIN" stop "${INST_UNIT[$i]}" && info "Snell v$major 已停止。"; else warn "Snell v$major 尚未安装。"; fi
        ;;
      6)
        if [[ -n $i ]]; then "$SYSTEMCTL_BIN" restart "${INST_UNIT[$i]}" && info "Snell v$major 已重启。"; else warn "Snell v$major 尚未安装。"; fi
        ;;
      7)
        if [[ -n $i ]]; then edit_instance "$i"; else warn "Snell v$major 尚未安装。"; fi
        ;;
      8)
        if [[ -n $i ]]; then view_instance "$i"; else warn "Snell v$major 尚未安装。"; fi
        ;;
      9)
        if [[ -n $i ]]; then "$SYSTEMCTL_BIN" status "${INST_UNIT[$i]}" --no-pager || true; else warn "Snell v$major 尚未安装。"; fi
        ;;
      00) return ;;
      *) warn "无效选项。" ;;
    esac
  done
}

main_menu() {
  local choice
  while true; do
    discover_instances
    printf '\n%s\nSnell v5/v6 多实例管理器 v%s\n%s\n' "$MENU_RULE" "$SCRIPT_VERSION" "$MENU_RULE"
    printf '1.管理 Snell v5\n2.管理 Snell v6\n3.查看 当前配置\n'
    printf '%s\n 00. 退出脚本\n%s\n\n' "$MENU_DIVIDER" "$MENU_RULE"
    printf ' 当前状态: '
    print_main_status
    printf '\n\n'
    read -r -p " 请输入数字[0-9]:" choice
    case "$choice" in
      1) major_menu 5 ;;
      2) major_menu 6 ;;
      3) view_current_configs ;;
      00) exit 0 ;;
      *) warn "无效选项。" ;;
    esac
  done
}

usage() {
  cat <<EOF
用法: sudo ./snell.sh [--audit|--help]

  无参数     打开交互式管理菜单
  --audit    只读发现并检查当前 Snell v5/v6 实例（PSK 遮盖）
  --help     显示帮助
EOF
}

main() {
  require_root
  require_supported_system
  case ${1:-} in
    --audit) audit ;;
    --help|-h) usage ;;
    "") main_menu ;;
    *) usage; exit 2 ;;
  esac
}

if [[ ${SNELL_TEST_MODE:-0} != 1 ]]; then
  main "$@"
fi
