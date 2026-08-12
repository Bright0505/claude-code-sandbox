#!/bin/bash
set -e

# Not being on a project network is a legitimate way to run the sandbox, but its
# failure mode is silent: every service name simply fails to resolve, which reads
# as "the whole environment is broken". Say which state we're in, out loud.
# SANDBOX_APP_NETWORK is set by sandbox.sh; see docs/KNOWN-ISSUES.md K-5.
print_network_summary() {
    if [ -n "${SANDBOX_APP_NETWORK:-}" ]; then
        printf 'sandbox: 已接上專案網路 %s —— 容器內用服務名連線，port 要用容器內部 port（不是 host 發布的 port）\n' \
            "$SANDBOX_APP_NETWORK"
    else
        printf '%s\n' \
            'sandbox: 未加入任何專案網路 —— 服務名不會解析，連不到本機其他容器。' \
            'sandbox: 這是啟動方式造成的，不是環境故障；要連接請用 ./sandbox.sh 啟動。'
    fi
}

# Container starts as root so the firewall can be configured, then drops
# to the unprivileged $USERNAME for everything else (matches Dockerfile.claude).
if [ "$(id -u)" = "0" ]; then
    /usr/local/bin/init-firewall.sh
    print_network_summary
    exec gosu claude "$@"
fi

print_network_summary
exec "$@"
