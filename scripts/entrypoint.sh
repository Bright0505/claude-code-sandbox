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

# Same failure shape as the network overlay (K-5): docker access is optional,
# and when it is off every docker command fails with a connection error that
# reads as a broken environment rather than as a deliberate configuration.
#
# This does not just report the configuration - it probes. A printed claim that
# turns out to be false is worse than printing nothing, because the next
# decision gets made on it. depends_on waits for the proxy's container to start,
# not for it to accept connections, so a short retry is the difference between
# "off" and "not up yet".
print_docker_summary() {
    if [ -z "${DOCKER_HOST:-}" ]; then
        printf '%s\n' \
            'sandbox: docker 存取未啟用 —— 容器內的 docker 指令會連不上。' \
            'sandbox: 這是啟動方式造成的，不是環境故障；要啟用請用 ./sandbox.sh 啟動。'
        return
    fi

    local i=0
    while [ "$i" -lt 5 ]; do
        if docker version >/dev/null 2>&1; then
            printf '%s\n' \
                "sandbox: docker 存取已啟用，經過濾 proxy ${DOCKER_HOST}" \
                'sandbox:   可用 —— exec／logs／ps／restart／up -d／build，限本專案的容器' \
                'sandbox:   不可用 —— 掛載 workspace 以外的路徑、--privileged、docker pull、' \
                'sandbox:              操作其他專案的容器、直接連 daemon'
            # compose 會把 `./` 這種相對 bind 路徑解析成「現在在哪個目錄」，而那個
            # 路徑要由 host 的 daemon 掛載 —— 在 /workspace 底下跑就會送出一個
            # host 上不存在的路徑，錯誤訊息是 daemon 的 mounts denied，看不出原因。
            if [ -n "${SANDBOX_HOST_WORKSPACE:-}" ]; then
                printf '%s\n' \
                    "sandbox:   ⚠️ 要跑 docker compose up／run 時先 cd ${SANDBOX_HOST_WORKSPACE}" \
                    'sandbox:      （同一棵樹，但路徑與 host 一致；在 /workspace 底下跑' \
                    'sandbox:      相對 bind 路徑會解析錯，daemon 會回 mounts denied）'
            fi
            return
        fi
        i=$((i + 1))
        sleep 1
    done

    printf '%s\n' \
        "sandbox: ⚠️ 設定了 DOCKER_HOST=${DOCKER_HOST} 但連不上過濾 proxy。" \
        'sandbox: docker 指令會失敗。這不是網路故障，是 proxy 沒起來 —— 檢查' \
        'sandbox: docker compose ps 裡的 docker-api-proxy 服務。' >&2
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
    print_docker_summary
    setup_git_auth gosu claude /usr/local/bin/setup-git-auth.sh
    exec gosu claude "$@"
fi

print_network_summary
print_docker_summary
setup_git_auth /usr/local/bin/setup-git-auth.sh
exec "$@"
