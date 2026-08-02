#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export SNELL_TEST_MODE=1
# shellcheck source=/dev/null
source "$ROOT/snell.sh"

failures=0
assert_eq() {
  local expected=$1 actual=$2 name=$3
  if [[ $expected == "$actual" ]]; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s (expected=%q actual=%q)\n' "$name" "$expected" "$actual"
    failures=$((failures+1))
  fi
}

assert_contains() {
  local haystack=$1 needle=$2 name=$3
  if [[ $haystack == *"$needle"* ]]; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s (missing=%q)\n' "$name" "$needle"
    failures=$((failures+1))
  fi
}

assert_not_contains() {
  local haystack=$1 needle=$2 name=$3
  if [[ $haystack != *"$needle"* ]]; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s (unexpected=%q)\n' "$name" "$needle"
    failures=$((failures+1))
  fi
}

assert_before() {
  local haystack=$1 first=$2 second=$3 name=$4
  if [[ $haystack == *"$first"*"$second"* ]]; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s (order=%q_before_%q)\n' "$name" "$first" "$second"
    failures=$((failures+1))
  fi
}

assert_cancel_step() {
  local name=$1 input=$2 rc=0 output
  shift 2
  output=$(printf '%b' "$input" | "$@" 2>&1) || rc=$?
  assert_eq 2 "$rc" "$name"
}

assert_eq "36847" "$(extract_port '::0:36847')" "parse legacy v5 listen"
assert_eq "36884" "$(extract_port '0.0.0.0:36884,[::]:36884')" "parse v6 multi-listen"
assert_eq "0.0.0.0:40000,[::]:40000" "$(replace_listen_port '0.0.0.0:36884,[::]:36884' 40000)" "replace all listen ports"
assert_eq "5" "$(major_from_version '5.0.1')" "v5 major"
assert_eq "6" "$(major_from_version '6.0.0')" "v6 major"
parsed=$(parse_exec_line '/usr/local/bin/snell-server -c /etc/snell/config.conf')
assert_eq $'/usr/local/bin/snell-server\t/etc/snell/config.conf' "$parsed" "parse systemd ExecStart"

tmp=$(mktemp -d /tmp/snell-manager-tests.XXXXXX)
trap 'rm -f "$tmp"/*; rmdir "$tmp"' EXIT
cat > "$tmp/config.conf" <<'EOF'
[snell-server]
listen = ::0:31325
psk = secret-value
ipv6 = true
EOF

assert_eq "secret-value" "$(config_value "$tmp/config.conf" psk)" "read PSK"
assert_eq "31325" "$(extract_port "$(config_value "$tmp/config.conf" listen)")" "BWH config without version"
write_key_to_temp "$tmp/config.conf" "$tmp/changed.conf" listen '::0:32000'
assert_eq "::0:32000" "$(config_value "$tmp/changed.conf" listen)" "atomic value rewrite"
assert_eq "[REDACTED]" "$(redacted_config "$tmp/config.conf" | awk -F'= ' '/psk/{print $2}')" "audit masks PSK"
assert_eq '[2001:db8::1]' "$(surge_endpoint '2001:db8::1')" "bracket IPv6 client endpoint"
assert_eq "true" "$(yes_no_value '' true)" "blank yes/no keeps true default"
assert_eq "false" "$(yes_no_value '' false)" "blank yes/no keeps false default"
assert_eq "confirm" "$(deploy_confirmation_value '')" "blank deployment confirmation proceeds"
assert_eq "confirm" "$(deploy_confirmation_value Y)" "explicit yes confirms deployment"
assert_eq "cancel" "$(deploy_confirmation_value N)" "negative deployment confirmation cancels"
assert_eq "cancel" "$(deploy_confirmation_value 00)" "00 deployment confirmation cancels"
assert_eq "invalid" "$(deploy_confirmation_value maybe)" "invalid deployment confirmation retries"
assert_eq 'node = snell, 203.0.113.10, 11967, psk=secret, version=5, tfo=true, reuse=true, ecn=true' \
  "$(build_surge_line node 203.0.113.10 11967 secret 5 '' '' '' true true true)" \
  "xOS-style native v5 client line"
assert_eq 'node = snell, 203.0.113.10, 11967, psk=secret, version=5, obfs=tls, obfs-host=cdn.example.com, tfo=true, reuse=true, ecn=true' \
  "$(build_surge_line node 203.0.113.10 11967 secret 5 '' tls cdn.example.com true true true)" \
  "xOS-style native v5 TLS client line"
assert_eq 'node-v4 = snell, example.com, 11967, psk=secret, version=4, obfs=http, obfs-host=cdn.example.com, tfo=true, reuse=true, ecn=true' \
  "$(build_surge_line node-v4 example.com 11967 secret 4 '' http cdn.example.com true true true)" \
  "v4 compatibility client line"
assert_eq 'node-v6 = snell, [2001:db8::1], 25346, psk=secret, version=6, mode=unshaped, tfo=true, reuse=true, ecn=true' \
  "$(build_surge_line node-v6 '2001:db8::1' 25346 secret 6 unshaped '' '' true true true)" \
  "xOS-style v6 client line"
write_server_config "$tmp/v5.conf" 5 11967 secret true '1.1.1.1, 8.8.8.8' false http cdn.example.com
assert_eq "http" "$(config_value "$tmp/v5.conf" obfs)" "render v5 HTTP obfs"
assert_eq "cdn.example.com" "$(config_value "$tmp/v5.conf" obfs-host)" "render v5 obfs host"
assert_eq "5" "$(config_value "$tmp/v5.conf" version)" "render v5 version"
write_server_config "$tmp/v5-tls.conf" 5 11968 secret true '1.1.1.1' false tls tls.example.com
assert_eq "tls" "$(config_value "$tmp/v5-tls.conf" obfs)" "render v5 TLS obfs"
assert_eq "tls.example.com" "$(config_value "$tmp/v5-tls.conf" obfs-host)" "render v5 TLS host"
write_server_config "$tmp/v6.conf" 6 25346 secret false '1.1.1.1' false off '' prefer-ipv4 unshaped
assert_eq "0.0.0.0:25346,[::]:25346" "$(config_value "$tmp/v6.conf" listen)" "render v6 dual listen"
assert_eq "prefer-ipv4" "$(config_value "$tmp/v6.conf" dns-ip-preference)" "render v6 DNS preference"
assert_eq "unshaped" "$(config_value "$tmp/v6.conf" mode)" "render v6 mode"
psk5=$(random_psk 5)
psk6=$(random_psk 6)
assert_eq "16" "${#psk5}" "xOS default v5 PSK length"
assert_eq "20" "${#psk6}" "xOS default v6 PSK length"

write_server_config "$tmp/summary-v5.conf" 5 36894 summary-secret true '1.1.1.1' false off
INST_CONF=("$tmp/summary-v5.conf")
INST_PORT=(36894)
INST_MAJOR=(5)
assert_eq 'US TEST = snell, 203.0.113.10, 36894, psk=summary-secret, version=5, reuse=true, tfo=true, ecn=true' \
  "$(summary_surge_line 0 203.0.113.10 'US TEST')" \
  "current config line with TFO and ECN"
INST_CONF=("$tmp/config.conf")
INST_PORT=(31325)
INST_MAJOR=(5)
assert_eq 'US LEGACY = snell, 198.51.100.20, 31325, psk=secret-value, version=5, reuse=true' \
  "$(summary_surge_line 0 198.51.100.20 'US LEGACY')" \
  "legacy current config line without TFO"
INST_MAJOR=(5 6)
find_major_instance 6
assert_eq "1" "$MAJOR_INDEX" "select instance by major version"
INST_ACTIVE=(active inactive)
discover_instances() { :; }
main_output=$(printf '00\n' | main_menu 2>&1)
assert_contains "$main_output" "1.管理 Snell v5" "new main menu v5 entry"
assert_contains "$main_output" "3.查看 当前配置" "new main menu current config entry"
assert_contains "$main_output" "$MENU_RULE" "main menu xOS title rule"
assert_contains "$main_output" "$MENU_DIVIDER" "main menu xOS divider"
assert_contains "$main_output" "v5:" "mixed main status includes v5"
assert_contains "$main_output" $'当前状态:\t\nv5:' "main status places v5 on its own line"
assert_contains "$main_output" $'\nv6:' "main status aligns v6 with v5"
assert_contains "$(declare -f main_menu)" 'read -r -p "请输入数字[0-9]:"' "main menu uses requested input prompt"
major_output=$(printf '00\n' | major_menu 5 2>&1)
assert_contains "$major_output" "1.安装 Snell v5" "v5 management install entry"
assert_contains "$major_output" "9.查看 运行状态" "version management status entry"
assert_contains "$major_output" "$MENU_DIVIDER" "management uses xOS divider"
assert_contains "$major_output" "00. 返回" "version management return entry"
assert_contains "$major_output" $'\n当前状态: ' "management status has no leading indentation"
assert_contains "$(declare -f major_menu)" 'read -r -p "请输入数字[0-9]:"' "management uses requested input prompt"

INST_UNIT=(snell-v5.service snell-v6.service)
INST_CONF=("$tmp/summary-v5.conf" "$tmp/v6.conf")
INST_PORT=(36894 37681)
INST_MAJOR=(5 6)
INST_ACTIVE=(active active)
public_ipv4() { printf '203.0.113.10'; }
public_ipv6() { printf '2001:db8::10'; }
hostname() { printf 'VM-TEST'; }
current_output=$(printf '\n' | view_current_configs)
assert_contains "$current_output" "$CONFIG_RULE" "current config uses long rule"
assert_contains "$current_output" "VM-TEST v5 = snell, 203.0.113.10, 36894" "current config renders v5 line"
assert_contains "$current_output" "VM-TEST v6 = snell, 203.0.113.10, 37681" "current config renders v6 line"
assert_contains "$current_output" $'ecn=true\n\n' "current config leaves blank line before footer"
assert_contains "$current_output" "* 按回车返回主菜单 *" "current config return prompt"
view_output=$(printf '\n' | view_instance 0)
assert_contains "$view_output" "Snell Server 配置信息：" "instance configuration title"
assert_contains "$view_output" $'IPv4 地址\t:' "instance configuration IPv4 field"
assert_contains "$view_output" $'IPv6 地址\t:' "instance configuration IPv6 field"
assert_contains "$view_output" "[信息]" "instance Surge information label"
assert_contains "$view_output" "VM-TEST = snell, 203.0.113.10, 36894" "instance Surge line"
assert_contains "$view_output" "* 按回车返回管理菜单 *" "instance returns to management menu"

INST_LISTEN=('0.0.0.0:36894' '0.0.0.0:37681,[::]:37681')
edit_v5_output=$(printf '0\n\n' | edit_instance 0 2>&1)
assert_contains "$edit_v5_output" "当前配置摘要" "v5 editor summary title"
assert_contains "$edit_v5_output" "$CONFIG_RULE" "v5 editor summary rule"
assert_contains "$edit_v5_output" "1. 端口: 36894" "v5 editor numbers current values"
assert_contains "$edit_v5_output" "2. PSK: summary-secret" "v5 editor shows plaintext PSK"
assert_contains "$edit_v5_output" "6. IPv6: false" "v5 editor IPv6 field"
assert_contains "$edit_v5_output" "8. OBFS Host:" "v5 editor OBFS host field"
assert_contains "$edit_v5_output" "请输入修改项[0-9]:" "configuration editor uses requested prompt"
assert_contains "$edit_v5_output" "* 按回车返回管理菜单 *" "configuration editor return prompt"

edit_v6_output=$(printf '0\n\n' | edit_instance 1 2>&1)
assert_contains "$edit_v6_output" "6. DNS IP 偏好: prefer-ipv4" "v6 editor DNS preference field"
assert_contains "$edit_v6_output" "8. listen: 0.0.0.0:37681,[::]:37681" "v6 editor listen field"

MANAGED_ETC="$tmp/managed-etc"
MANAGED_LIB="$tmp/managed-lib"
SYSTEMD_DIR="$tmp/systemd"
INST_MAJOR=()
port_calls=0
port_free() {
  port_calls=$((port_calls+1))
  ((port_calls > 1))
}
install_set_port < <(printf '\n3456\n') >"$tmp/port-retry-output" 2>&1
assert_eq "3456" "$INSTALL_PORT" "occupied default port is entered again"
assert_contains "$(<"$tmp/port-retry-output")" "已被占用" "occupied port warning is visible"

install_set_psk 5 < <(printf 'short\n1234567890abcdef\n') >"$tmp/psk-retry-output" 2>&1
assert_eq "1234567890abcdef" "$INSTALL_PSK" "invalid v5 PSK is entered again"
assert_contains "$(<"$tmp/psk-retry-output")" "16 到 255 位" "invalid PSK warning is visible"

install_set_mode < <(printf '3\nNO\n2\n') >"$tmp/mode-retry-output" 2>&1
assert_eq "unshaped" "$INSTALL_MODE" "unconfirmed unsafe-raw returns to mode selection"

port_free() { return 0; }
deploy_v5_output=$(printf '\n\n\n\n\n\nN\n' | deploy_major 5 2>&1)
assert_contains "$deploy_v5_output" "请输入 Snell Server 端口" "xOS-style install port prompt"
assert_contains "$deploy_v5_output" "请输入 Snell Server 密钥" "xOS-style install PSK prompt"
assert_contains "$deploy_v5_output" "配置 OBFS" "xOS-style v5 OBFS prompt"
assert_contains "$deploy_v5_output" "是否开启 IPv6 解析？" "xOS-style v5 IPv6 prompt"
assert_contains "$deploy_v5_output" "是否开启 TCP Fast Open？" "xOS-style v5 TFO prompt"
assert_contains "$deploy_v5_output" "默认值" "xOS-style DNS prompt"
assert_contains "$deploy_v5_output" "$INSTALL_RULE" "install option pages use xOS rule"
assert_contains "$deploy_v5_output" "端口: 2345" "deployment summary port label"
assert_contains "$deploy_v5_output" "TFO: true" "deployment summary TFO label"
assert_contains "$deploy_v5_output" "IPv6: false" "deployment summary IPv6 label"
assert_contains "$deploy_v5_output" "PSK: " "deployment summary includes PSK"
assert_not_contains "$deploy_v5_output" "PSK: [已设置" "deployment summary does not mask PSK"
assert_contains "$deploy_v5_output" "确认部署？[Y/n]: " "deployment confirmation defaults to yes"
assert_before "$deploy_v5_output" "配置 OBFS" "是否开启 IPv6 解析？" "v5 OBFS precedes IPv6"
assert_before "$deploy_v5_output" "是否开启 IPv6 解析？" "是否开启 TCP Fast Open？" "v5 IPv6 precedes TFO"
assert_before "$deploy_v5_output" "是否开启 TCP Fast Open？" "请输入正确格式的 DNS" "v5 TFO precedes DNS"

deploy_v6_output=$(printf '\n\n\n\n\n\nN\n' | deploy_major 6 2>&1)
assert_contains "$deploy_v6_output" "是否开启 TCP Fast Open？" "v6 install TFO prompt"
assert_contains "$deploy_v6_output" "配置 DNS IP 偏好" "v6 install DNS preference prompt"
assert_contains "$deploy_v6_output" "配置 混淆模式" "v6 install mode prompt"
assert_not_contains "$deploy_v6_output" "配置 OBFS" "v6 install omits OBFS"
assert_not_contains "$deploy_v6_output" "是否开启 IPv6 解析？" "v6 install omits IPv6 resolver prompt"
assert_before "$deploy_v6_output" "是否开启 TCP Fast Open？" "请输入正确格式的 DNS" "v6 TFO precedes DNS"
assert_before "$deploy_v6_output" "配置 DNS IP 偏好" "配置 混淆模式" "v6 DNS preference precedes mode"

assert_cancel_step "port step supports 00 cancellation" '00\n' install_set_port
assert_cancel_step "v5 PSK step supports 00 cancellation" '00\n' install_set_psk 5
assert_cancel_step "v6 PSK step supports 00 cancellation" '00\n' install_set_psk 6
assert_cancel_step "OBFS step supports 00 cancellation" '00\n' install_set_obfs
assert_cancel_step "IPv6 step supports 00 cancellation" '00\n' install_set_ipv6
assert_cancel_step "TFO step supports 00 cancellation" '00\n' install_set_tfo
assert_cancel_step "DNS step supports 00 cancellation" '00\n' install_set_dns
assert_cancel_step "DNS preference supports 00 cancellation" '00\n' install_set_dns_preference
assert_cancel_step "mode supports 00 cancellation" '00\n' install_set_mode
assert_cancel_step "unsafe-raw confirmation supports 00 cancellation" '3\n00\n' install_set_mode

install_set_obfs < <(printf '1\nexample.com\n') >"$tmp/tls-output" 2>&1
tls_output=$(<"$tmp/tls-output")
assert_eq "tls" "$INSTALL_OBFS" "OBFS menu selects TLS"
assert_eq "example.com" "$INSTALL_OBFS_HOST" "OBFS menu stores TLS host"
assert_contains "$tls_output" "OBFS 状态" "OBFS result is displayed"

INST_VERSION=(5.0.1)
INST_MAJOR=(5)
INST_BIN=("$tmp/snell-server")
INST_UNIT=(snell-v5.service)
update_output=$(printf 'N\n\n' | update_instance 0 2>&1)
assert_contains "$update_output" "当前 v5.0.1；目标官方包 5.0.1。" "update confirmation versions"
assert_contains "$update_output" "确认更新 [y/N]: " "update confirmation prompt"
assert_contains "$update_output" "* 按回车返回管理菜单 *" "update return prompt"

fake_systemctl() {
  printf '%s\n' '● snell-v5.service - Snell v5 managed instance' \
    '   Loaded: loaded (/etc/systemd/system/snell-v5.service; enabled)' \
    '   Active: active (running)' \
    ' Main PID: 1234 (snell-server)'
}
SYSTEMCTL_BIN=fake_systemctl
status_output=$(printf '\n' | view_instance_status 0 2>&1)
assert_contains "$status_output" "● snell-v5.service - Snell v5 managed instance" "status page service output"
assert_contains "$status_output" "$CONFIG_RULE" "status page rule"
assert_contains "$status_output" "* 按回车返回管理菜单 *" "status page return prompt"
assert_contains "$(declare -f firewall_offer)" "[y/N]: " "firewall confirmation defaults to no"
assert_not_contains "$(declare -f firewall_offer)" "answer=y" "firewall blank input does not auto-approve"

if ((failures)); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all tests passed\n'
