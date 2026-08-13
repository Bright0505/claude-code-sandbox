#!/bin/bash
# Tests for init-firewall.sh's domain wiring (which hosts end up in the
# allowlist), without touching this machine's actual network.
#
# init-firewall.sh needs root + iptables/ipset/dig, and running it for real would
# reconfigure the host's firewall. So the four commands it shells out to are
# shadowed by stubs on PATH and the *real shipped script* is executed against
# them - this tests the shipped code, not a copy of its logic.
#
#   ./scripts/test-init-firewall.sh
set -uo pipefail

unset GITHUB_HOST GH_HOST GITLAB_HOST EXTRA_ALLOWED_DOMAINS

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIREWALL="$SCRIPT_DIR/init-firewall.sh"
LIB="$SCRIPT_DIR/git-forge-lib.sh"

pass=0
fail=0
ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no() {
    printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fail=$((fail + 1))
}
check() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2" "$3"; fi; }

# Exact whole-entry match. `grep -w github.com` would also match inside
# api.github.com, which silently weakened these assertions (2026-08-13).
in_list() { # $1=domain $2=allowlist
    if printf '%s\n' $2 | grep -qx "$1"; then echo yes; else echo no; fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stubs="$tmp/stubs"
mkdir -p "$stubs"

# `dig` resolves everything to a fixed address except hosts whose name contains
# "unresolvable", which resolve to nothing - that is the case the script must
# warn about instead of skipping silently.
cat > "$stubs/dig" <<'EOF'
#!/bin/bash
for arg in "$@"; do domain="$arg"; done
case "$domain" in
    *unresolvable*) exit 0 ;;
    *) echo 192.0.2.1 ;;
esac
EOF
cat > "$stubs/iptables" <<'EOF'
#!/bin/bash
echo "iptables $*" >> "$STUB_LOG"
EOF
cat > "$stubs/ipset" <<'EOF'
#!/bin/bash
echo "ipset $*" >> "$STUB_LOG"
EOF
cat > "$stubs/ip" <<'EOF'
#!/bin/bash
echo "2: eth0    inet 172.31.0.2/16 brd 172.31.255.255 scope global eth0"
EOF
chmod +x "$stubs"/*

# Echoes the script's final "egress restricted to: ..." line.
allowlist() {
    env "PATH=$stubs:$PATH" "STUB_LOG=$tmp/log" "GIT_FORGE_LIB=$LIB" "$@" \
        bash "$FIREWALL" 2>&1 | sed -n 's/^init-firewall: egress restricted to: //p'
}
run_firewall() {
    env "PATH=$stubs:$PATH" "STUB_LOG=$tmp/log" "GIT_FORGE_LIB=$LIB" "$@" \
        bash "$FIREWALL" 2>&1
}

printf '\n== 預設白名單 ==\n'
list="$(allowlist)"
check 'github.com 在內'  'yes' "$(in_list github.com "$list")"
check 'gitlab.com 在內'  'yes' "$(in_list gitlab.com "$list")"
check 'api.anthropic.com 還在（沒改壞既有的）' 'yes' \
    "$(in_list api.anthropic.com "$list")"
# github.com is both in the static list and derived from forge_github_host, so
# this is the dedupe assertion.
check 'github.com 只出現一次' '1' \
    "$(printf '%s\n' $list | grep -cx 'github.com')"

printf '\n== 自架站台 ==\n'
list="$(allowlist GITLAB_HOST=https://git.corp.example/group)"
check 'GITLAB_HOST 的 host 被加入' 'yes' \
    "$(in_list git.corp.example "$list")"
check 'URL 的路徑沒被當成 host' 'no' \
    "$(printf '%s' "$list" | grep -q 'group' && echo yes || echo no)"   # substring on purpose
list="$(allowlist GITHUB_HOST=gh.corp.example)"
check 'GITHUB_HOST 的 host 被加入' 'yes' \
    "$(in_list gh.corp.example "$list")"

# Intent: configuring a self-hosted host *adds* to the allowlist, it does not
# replace the public hosts - glab's own update/telemetry calls and any public
# repo still go to gitlab.com. Without this assertion the static gitlab.com entry
# in the script is not load-bearing: forge_gitlab_host defaults to it anyway, so
# deleting the static entry leaves every other test green (found by mutation
# testing, 2026-08-13).
list="$(allowlist GITLAB_HOST=git.corp.example GITHUB_HOST=gh.corp.example)"
check '設了自架站台時 gitlab.com 仍在白名單' 'yes' \
    "$(in_list gitlab.com "$list")"
check '設了自架站台時 github.com 仍在白名單' 'yes' \
    "$(in_list github.com "$list")"

printf '\n== EXTRA_ALLOWED_DOMAINS ==\n'
list="$(allowlist EXTRA_ALLOWED_DOMAINS='a.example.com,b.example.com c.example.com')"
for d in a.example.com b.example.com c.example.com; do
    check "$d（逗號與空白都吃）" 'yes' \
        "$(in_list "$d" "$list")"
done

printf '\n== 解析失敗要警告，不能沉默 ==\n'
out="$(run_firewall EXTRA_ALLOWED_DOMAINS='nope.unresolvable.example')"
check '印出無法解析的警告' 'yes' \
    "$(printf '%s' "$out" | grep -q '無法解析 nope.unresolvable.example' && echo yes || echo no)"

printf '\n== 真的有把解析到的 IP 加進 ipset ==\n'
: > "$tmp/log"
run_firewall >/dev/null
check 'ipset add 被呼叫' 'yes' \
    "$(grep -q '^ipset add allowed-domains 192.0.2.1' "$tmp/log" && echo yes || echo no)"
check '本機子網段有放行（既有行為）' 'yes' \
    "$(grep -q 'iptables -A OUTPUT -o eth0 -d 172.31.0.2/16 -j ACCEPT' "$tmp/log" && echo yes || echo no)"

printf '\n通過 %s，失敗 %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
