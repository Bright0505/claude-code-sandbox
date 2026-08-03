#!/bin/bash
# Restrict container egress to the domains Claude Code actually needs.
# Must run as root (before dropping to the unprivileged user) since it
# touches iptables/ipset.
set -euo pipefail

iptables -F
iptables -X
ipset destroy allowed-domains 2>/dev/null || true

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Loopback + established connections
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# DNS
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A INPUT -p tcp --sport 53 -j ACCEPT

# Allow east-west traffic to whatever Docker network(s) this container is
# actually attached to (e.g. a project's own app-net joined via
# docker-compose.claude.network.yml), so sibling containers like an API or
# DB are reachable by service name. Scoped to the attached subnets only -
# does not open up RFC1918 space in general.
for iface in $(find /sys/class/net -mindepth 1 -maxdepth 1 -type l -printf '%f\n' 2>/dev/null | grep -v '^lo$' || true); do
    cidr="$(ip -4 -o addr show "$iface" 2>/dev/null | awk '{print $4}' || true)"
    if [ -n "$cidr" ]; then
        iptables -A OUTPUT -o "$iface" -d "$cidr" -j ACCEPT
        iptables -A INPUT -i "$iface" -s "$cidr" -j ACCEPT
        echo "init-firewall: allowing local subnet $cidr on $iface"
    fi
done

ipset create allowed-domains hash:ip

ALLOWED_DOMAINS=(
    api.anthropic.com
    console.anthropic.com
    statsig.anthropic.com
    sentry.io
    github.com
    api.github.com
    raw.githubusercontent.com
    objects.githubusercontent.com
    codeload.github.com
    registry.npmjs.org
    pypi.org
    files.pythonhosted.org
)

for domain in "${ALLOWED_DOMAINS[@]}"; do
    ips="$(dig +short A "$domain" | grep -E '^[0-9.]+$' || true)"
    for ip in $ips; do
        ipset add allowed-domains "$ip" 2>/dev/null || true
    done
done

iptables -A OUTPUT -m set --match-set allowed-domains dst -p tcp --dport 443 -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -m set --match-set allowed-domains src -p tcp --sport 443 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -m set --match-set allowed-domains src -p tcp --sport 80 -m state --state ESTABLISHED -j ACCEPT

echo "init-firewall: egress restricted to: ${ALLOWED_DOMAINS[*]}"
