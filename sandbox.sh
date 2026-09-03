#!/usr/bin/env bash
#
# 啟動 sandbox 並接上專案自己的 docker 網路，讓容器內能用服務名連到已啟動的服務。
#
# 為什麼需要這支：手動疊 overlay 要同時記住兩個 -f、WORKSPACE_DIR、APP_NETWORK_NAME，
# 而漏掉任何一項時**失敗是靜默的** —— 沒有錯誤訊息，只是所有服務名都解析不到，
# 讀起來像整個環境壞掉 —— 而「整個壞了」這個解釋會擴散成錯誤的工作決策。
# 所以這支的存在本身就是修法：把接上網路變成預設路徑，而不是一個要記得帶的選項。
#
# 用法：
#   ./sandbox.sh                啟動 claude
#   ./sandbox.sh bash           取得 shell
#   ./sandbox.sh claude --help  參數原樣透傳
#
# 環境變數（都可省略，省略時自動推導；推導結果一律印出來）：
#   WORKSPACE_DIR        掛進 /workspace 的目錄
#   APP_NETWORK_NAME     要加入的 docker 網路名；設了就跳過自動偵測
#   APP_COMPOSE_PROJECT  專案的 compose project 名，供自動偵測使用
#   SANDBOX_DOCKER       1（預設）啟用容器內的 docker 存取；0 關閉
#
# 這支跑在 host，不是在容器內。容器內有 docker CLI，但 DOCKER_HOST 指向一支
# 過濾 proxy，不是真的 socket —— 邊界見 docker-compose.claude.docker.yml。
set -euo pipefail

SANDBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf '%s\n' "$@" >&2; exit 1; }

command -v docker >/dev/null 2>&1 \
    || die "找不到 docker CLI。這支腳本要在 host 上執行，不是在 sandbox 容器內。"

# --- 決定 WORKSPACE_DIR ------------------------------------------------------
# 當 sandbox 被當成 submodule／vendored 目錄放進另一個專案時，要掛的是**外層專案**
# 的根目錄而不是 sandbox 自己。用父目錄是否為 git 工作區來判斷，而不是
# `git rev-parse --show-superproject-working-tree` —— 後者在「已 clone 但該分支
# 還沒 track 這個 submodule」時會回空字串，正是最容易發生的狀態。
if [ -z "${WORKSPACE_DIR:-}" ]; then
    outer="$(git -C "$(dirname "$SANDBOX_DIR")" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$outer" ] && [ "$outer" != "$SANDBOX_DIR" ]; then
        WORKSPACE_DIR="$outer"
    else
        WORKSPACE_DIR="$SANDBOX_DIR"
    fi
fi
[ -d "$WORKSPACE_DIR" ] || die "WORKSPACE_DIR 不存在：$WORKSPACE_DIR"
WORKSPACE_DIR="$(cd "$WORKSPACE_DIR" && pwd)"

# --- 決定要加入哪個網路 ------------------------------------------------------
# compose 會在自己建的網路上打 com.docker.compose.project 這個 label，
# 所以不需要要求專案去把網路改名成某個固定值 —— 直接照 project 名反查即可。
COMPOSE_PROJECT="${APP_COMPOSE_PROJECT:-$(basename "$WORKSPACE_DIR")}"

list_compose_networks() {
    docker network ls --filter 'label=com.docker.compose.project' \
        --format '  {{.Name}}  (project={{.Label "com.docker.compose.project"}})' 2>/dev/null
}

if [ -z "${APP_NETWORK_NAME:-}" ]; then
    if ! nets="$(docker network ls \
            --filter "label=com.docker.compose.project=$COMPOSE_PROJECT" \
            --format '{{.Name}}' 2>&1)"; then
        die "docker network ls 失敗（docker daemon 沒在跑？）：" "$nets"
    fi

    count="$(printf '%s\n' "$nets" | grep -c . || true)"

    if [ "$count" -eq 0 ]; then
        die "找不到 compose project \"$COMPOSE_PROJECT\" 的 docker 網路。" \
            "" \
            "依可能性排序：" \
            "  1. 專案服務還沒啟動 → 在 $WORKSPACE_DIR 執行 docker compose up -d" \
            "  2. compose project 名不是 \"$COMPOSE_PROJECT\"（專案的 compose 有 name:，" \
            "     或設了 COMPOSE_PROJECT_NAME）→ APP_COMPOSE_PROJECT=<實際名稱> $0" \
            "  3. 網路不是 compose 建的 → APP_NETWORK_NAME=<網路名> $0" \
            "" \
            "目前主機上的 compose 網路：" \
            "$(list_compose_networks)"
    fi

    if [ "$count" -gt 1 ]; then
        die "compose project \"$COMPOSE_PROJECT\" 有 $count 個網路，無法判斷要加入哪一個：" \
            "$(printf '%s\n' "$nets" | sed 's/^/  /')" \
            "" \
            "請指定：APP_NETWORK_NAME=<上列其一> $0"
    fi

    APP_NETWORK_NAME="$nets"
fi

docker network inspect "$APP_NETWORK_NAME" >/dev/null 2>&1 \
    || die "docker 網路不存在：$APP_NETWORK_NAME" \
           "" \
           "目前主機上的 compose 網路：" \
           "$(list_compose_networks)"

# --- 決定要不要給 docker 存取 ------------------------------------------------
# 預設開啟。理由跟網路 overlay 同一條：留了選用機制卻不做成預設路徑，
# 實務上等於預設關閉，而關閉時的失敗長得跟環境故障一模一樣。
SANDBOX_DOCKER="${SANDBOX_DOCKER:-1}"

COMPOSE_FILES=(
    -f "$SANDBOX_DIR/docker-compose.claude.yml"
    -f "$SANDBOX_DIR/docker-compose.claude.network.yml"
)
if [ "$SANDBOX_DOCKER" = "1" ]; then
    COMPOSE_FILES+=(-f "$SANDBOX_DIR/docker-compose.claude.docker.yml")
fi

# --- 啟動 --------------------------------------------------------------------
[ "$#" -eq 0 ] && set -- claude

# 只印推導結果；「這代表什麼」由容器內的 entrypoint 說，避免兩邊各講一次。
printf 'sandbox: workspace = %s\n' "$WORKSPACE_DIR"
printf 'sandbox: 專案網路 = %s\n' "$APP_NETWORK_NAME"
printf 'sandbox: compose project = %s\n' "$COMPOSE_PROJECT"
if [ "$SANDBOX_DOCKER" = "1" ]; then
    printf 'sandbox: docker 存取 = 啟用（經過濾 proxy）\n'
else
    printf 'sandbox: docker 存取 = 關閉（SANDBOX_DOCKER=%s）\n' "$SANDBOX_DOCKER"
fi

# SANDBOX_APP_NETWORK 傳進容器只為了讓 entrypoint 能印出「接上了什麼」；
# 真正接上網路的是上面那個 overlay。
# APP_COMPOSE_PROJECT 則是給 proxy 用的：它決定哪些容器可以被操作。
run_sandbox() {
    env \
        WORKSPACE_DIR="$WORKSPACE_DIR" \
        APP_NETWORK_NAME="$APP_NETWORK_NAME" \
        APP_COMPOSE_PROJECT="$COMPOSE_PROJECT" \
        docker compose "${COMPOSE_FILES[@]}" \
            run --rm \
            -e SANDBOX_APP_NETWORK="$APP_NETWORK_NAME" \
            claude-sandbox "$@"
}

# 不用 exec：proxy 持有 docker.sock，session 結束後不該留著。`run --rm` 只清掉
# sandbox 自己的容器，不會動 depends_on 起來的服務。
# `|| rc=$?` 而不是直接 `rc=$?`：set -e 會在非零離開時直接中止腳本，
# 清理就不會跑，proxy 會留著持有 docker.sock。
rc=0
run_sandbox "$@" || rc=$?

if [ "$SANDBOX_DOCKER" = "1" ]; then
    env WORKSPACE_DIR="$WORKSPACE_DIR" \
        APP_NETWORK_NAME="$APP_NETWORK_NAME" \
        APP_COMPOSE_PROJECT="$COMPOSE_PROJECT" \
        docker compose "${COMPOSE_FILES[@]}" rm -sf docker-api-proxy >/dev/null 2>&1 \
        || printf 'sandbox: ⚠️ 未能移除 docker-api-proxy 容器，它仍持有 docker.sock。\n' >&2
fi

exit "$rc"
