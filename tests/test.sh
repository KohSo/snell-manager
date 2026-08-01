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
assert_eq '[2001:db8::1]' "$(surge_endpoint '2001:db8::1')" "bracket IPv6 client endpoint"
assert_eq "true" "$(yes_no_value '' true)" "blank yes/no keeps true default"
assert_eq "false" "$(yes_no_value '' false)" "blank yes/no keeps false default"
assert_eq 'node = snell, 203.0.113.10, 11967, psk=secret, version=5, tfo=true, reuse=true, ecn=true' \
  "$(build_surge_line node 203.0.113.10 11967 secret 5 '' '' '' true true true)" \
  "xOS-style native v5 client line"
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
write_server_config "$tmp/v6.conf" 6 25346 secret false '1.1.1.1' false off '' prefer-ipv4 unshaped
assert_eq "0.0.0.0:25346,[::]:25346" "$(config_value "$tmp/v6.conf" listen)" "render v6 dual listen"
assert_eq "prefer-ipv4" "$(config_value "$tmp/v6.conf" dns-ip-preference)" "render v6 DNS preference"
assert_eq "unshaped" "$(config_value "$tmp/v6.conf" mode)" "render v6 mode"
psk5=$(random_psk 5)
psk6=$(random_psk 6)
assert_eq "16" "${#psk5}" "xOS default v5 PSK length"
assert_eq "20" "${#psk6}" "xOS default v6 PSK length"

if ((failures)); then
  printf '%s test(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'all tests passed\n'
