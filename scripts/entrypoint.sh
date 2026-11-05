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

# Same failure shape as the network overlay: docker access is optional,
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

# Peer messaging is opt-in (docker-compose.claude.peer.yml). Same rule as the
# two summaries above: say which state we are in, on both paths.
PEER_SESSIONS_DIR=/home/claude/.claude/sessions
PEER_SOCKS_DIR=/tmp/cc-socks

print_peer_summary() {
    if [ -n "${SANDBOX_PEER_GROUP:-}" ]; then
        printf '%s\n' \
            "sandbox: 已加入協作群組 ${SANDBOX_PEER_GROUP} —— 同群組其他 sandbox 的 Claude session 可互相看見、互傳訊息" \
            'sandbox:   同群組＝互相信任：對方能送訊息進來，也讀得到 sessions/ 裡的 .key'
    else
        printf '%s\n' \
            'sandbox: 未加入協作群組 —— 看不到其他 sandbox 的 Claude session。' \
            'sandbox: 這是啟動方式造成的；要加入請用 SANDBOX_PEER_GROUP=<名稱> ./sandbox.sh 啟動。'
    fi
}

# Fresh named volumes are root-owned, and Claude Code silently skips peer
# registration when the directory is not its own (measured: no <pid>.json, no
# socket, no error). So hand them to the unprivileged user before dropping.
prepare_peer_dirs() {
    chown claude:claude "$PEER_SESSIONS_DIR" "$PEER_SOCKS_DIR"
}

# Every container has its own PID namespace, so every claude would otherwise be
# the same small PID - and the shared registry is named by PID, so the later
# session silently overwrites the earlier one's entry. Burn a random number of
# PIDs, and keep going until the NEXT pid is unregistered; the very next fork
# is the one that becomes claude (gosu execs, keeping the PID).
# Sets PEER_PID to the PID the next child will get. A global, not $(...):
# command substitution is itself a fork, and nothing may fork between here
# and the child.
advance_to_free_pid() {
    local target=$(( 1000 + RANDOM % 20000 )) n=0 p cand
    while :; do
        /bin/true & p=$!
        wait "$p"
        n=$((n + 1))
        cand=$((p + 1))
        if [ "$n" -ge "$target" ] \
                && [ ! -e "$PEER_SESSIONS_DIR/$cand.json" ] \
                && [ ! -e "$PEER_SOCKS_DIR/$cand.sock" ]; then
            PEER_PID="$cand"
            return
        fi
    done
}

# Runs "$@" as a child on a free PID and exits with its status. Not exec: exec
# keeps this script's PID, which is the same in every container.
run_as_peer() {
    local rc=0
    advance_to_free_pid
    printf 'sandbox:   這個 session 的 PID = %s\n' "$PEER_PID"
    "$@" || rc=$?
    exit "$rc"
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
    print_peer_summary
    setup_git_auth gosu claude /usr/local/bin/setup-git-auth.sh
    if [ -n "${SANDBOX_PEER_GROUP:-}" ]; then
        prepare_peer_dirs
        run_as_peer gosu claude "$@"
    fi
    exec gosu claude "$@"
fi

print_network_summary
print_docker_summary
print_peer_summary
setup_git_auth /usr/local/bin/setup-git-auth.sh
[ -n "${SANDBOX_PEER_GROUP:-}" ] && run_as_peer "$@"
exec "$@"
