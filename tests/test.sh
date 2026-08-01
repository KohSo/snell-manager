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

if ((failures)); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all tests passed\n'
