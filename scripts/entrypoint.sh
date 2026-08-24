#!/bin/bash
set -e

# Not being on a project network is a legitimate way to run the sandbox, but its
# failure mode is silent: every service name simply fails to resolve, which reads
# as "the whole environment is broken". Say which state we're in, out loud.
# SANDBOX_APP_NETWORK is set by sandbox.sh. Printing on *both* paths is the
# point: with output only on success, "no line" and "not reached yet" look the same.
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

# Token-based git auth is a convenience, not a guardrail: if it breaks the
# container must still start - but loudly, because the failure downstream is a
# credential prompt or a hang, which reads as a broken environment.
setup_git_auth() {
    if ! "$@"; then
        printf '%s\n' \
            'sandbox: ⚠️ git 認證設定失敗（原因見上方輸出）。容器照常啟動，' \
            'sandbox: 但 push 會要求帳號密碼。' >&2
    fi
}

# Container starts as root so the firewall can be configured, then drops
# to the unprivileged $USERNAME for everything else (matches Dockerfile.claude).
# git auth is configured as that same unprivileged user, so ~/.gitconfig belongs
# to whoever actually runs git.
if [ "$(id -u)" = "0" ]; then
    /usr/local/bin/init-firewall.sh
    print_network_summary
    setup_git_auth gosu claude /usr/local/bin/setup-git-auth.sh
    exec gosu claude "$@"
fi

print_network_summary
setup_git_auth /usr/local/bin/setup-git-auth.sh
exec "$@"
