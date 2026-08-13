#!/bin/bash
# Tests for git-forge-lib.sh / git-credential-env.sh / setup-git-auth.sh.
#
# Runs on the host with nothing but bash + git - no docker daemon, no image
# build, no real token. What it cannot cover is listed at the end of
# docs/tasks/2026-08-13-git-forge-token-auth.md.
#
#   ./scripts/test-git-auth.sh
set -uo pipefail

# The suite must not inherit forge settings from whoever runs it - a GITHUB_TOKEN
# exported by the surrounding shell would make the "no token" assertions pass for
# the wrong reason.
unset GITHUB_TOKEN GH_TOKEN GITLAB_TOKEN GITLAB_ACCESS_TOKEN \
      GITHUB_HOST GH_HOST GITLAB_HOST GITHUB_USER GITLAB_USER \
      SANDBOX_GIT_REWRITE_SSH SANDBOX_WORKSPACE
export GIT_CONFIG_NOSYSTEM=1   # ignore /etc/gitconfig, whatever the host has in it

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB="$SCRIPT_DIR/git-forge-lib.sh"
HELPER="$SCRIPT_DIR/git-credential-env.sh"
SETUP="$SCRIPT_DIR/setup-git-auth.sh"

pass=0
fail=0

ok() { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
no() {
    printf '  FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fail=$((fail + 1))
}
check() { # $1=name $2=expected $3=actual
    if [ "$2" = "$3" ]; then ok "$1"; else no "$1" "$2" "$3"; fi
}

# Runs the credential helper in a scrubbed environment so a stray variable in
# the caller's shell cannot make a test pass. Usage:
#   run_helper <stdin> <verb> [VAR=value ...]
run_helper() {
    local input="$1" verb="$2"
    shift 2
    printf '%s' "$input" | env -i "PATH=$PATH" "GIT_FORGE_LIB=$LIB" "$@" \
        bash "$HELPER" "$verb"
}

printf '\n== git-forge-lib: host 正規化 ==\n'
# shellcheck source=./git-forge-lib.sh
. "$LIB"
check 'bare host'          'gitlab.example.com' "$(forge_normalize_host 'gitlab.example.com')"
check 'https URL'          'gitlab.example.com' "$(forge_normalize_host 'https://gitlab.example.com')"
check 'URL + 尾斜線與路徑' 'gitlab.example.com' "$(forge_normalize_host 'https://gitlab.example.com/group/x')"
check 'host:port'          'gitlab.example.com' "$(forge_normalize_host 'gitlab.example.com:8443')"
check '空字串'             ''                   "$(forge_normalize_host '')"

printf '\n== git-forge-lib: 環境變數解讀 ==\n'
check 'GitHub host 預設'   'github.com'         "$(forge_github_host)"
check 'GitLab host 預設'   'gitlab.com'         "$(forge_gitlab_host)"
check 'GH_HOST 也認'       'gh.corp.example'    "$(GH_HOST=gh.corp.example forge_github_host)"
check 'GITHUB_TOKEN 優先'  'a'                  "$(GITHUB_TOKEN=a GH_TOKEN=b forge_github_token)"
check 'GH_TOKEN 備援'      'b'                  "$(GH_TOKEN=b forge_github_token)"
check 'GITLAB_TOKEN 優先'  'c'                  "$(GITLAB_TOKEN=c GITLAB_ACCESS_TOKEN=d forge_gitlab_token)"
check 'username 預設'      'x-access-token'     "$(forge_github_user)"
check 'username 可覆寫'    'me'                 "$(GITHUB_USER=me forge_github_user)"

check 'GitLab host 來自 env' 'git.corp.example' \
    "$(GITLAB_HOST=https://git.corp.example/g/x forge_gitlab_host)"

printf '\n== credential helper: 有 token 時的回答 ==\n'
GH_IN='protocol=https
host=github.com

'
check 'github.com + GITHUB_TOKEN' \
    'username=x-access-token
password=tok-gh' \
    "$(run_helper "$GH_IN" get GITHUB_TOKEN=tok-gh)"

check 'GITHUB_USER 覆寫 username' \
    'username=alice
password=tok-gh' \
    "$(run_helper "$GH_IN" get GITHUB_TOKEN=tok-gh GITHUB_USER=alice)"

check 'gitlab.com + GITLAB_TOKEN' \
    'username=oauth2
password=tok-gl' \
    "$(run_helper 'protocol=https
host=gitlab.com

' get GITLAB_TOKEN=tok-gl)"

check '自架 GITLAB_HOST（URL 形式）' \
    'username=oauth2
password=tok-gl' \
    "$(run_helper 'protocol=https
host=git.corp.example

' get GITLAB_TOKEN=tok-gl GITLAB_HOST=https://git.corp.example/)"

check 'host 帶 port 仍比對得上' \
    'username=oauth2
password=tok-gl' \
    "$(run_helper 'protocol=https
host=git.corp.example:8443

' get GITLAB_TOKEN=tok-gl GITLAB_HOST=git.corp.example:8443)"

printf '\n== credential helper: 該沉默的時候 ==\n'
check '沒設 token'         '' "$(run_helper "$GH_IN" get)"
check '不認識的 host'      '' "$(run_helper 'protocol=https
host=bitbucket.org

' get GITHUB_TOKEN=tok-gh GITLAB_TOKEN=tok-gl)"
check 'protocol=http 不給' '' "$(run_helper 'protocol=http
host=github.com

' get GITHUB_TOKEN=tok-gh)"
check 'store 不輸出'       '' "$(run_helper "$GH_IN" store GITHUB_TOKEN=tok-gh)"
check 'erase 不輸出'       '' "$(run_helper "$GH_IN" erase GITHUB_TOKEN=tok-gh)"

run_helper "$GH_IN" erase GITHUB_TOKEN=tok-gh >/dev/null 2>&1
check 'erase 的 exit code' '0' "$?"

printf '\n== setup-git-auth：實際跑一次，檢查 .gitconfig ==\n'
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/home" "$tmp/bin"
# git resolves the helper name `sandbox-env` via PATH, exactly as in the image.
cp "$HELPER" "$tmp/bin/git-credential-sandbox-env"
chmod +x "$tmp/bin/git-credential-sandbox-env"

setup_out="$(env -i "PATH=$tmp/bin:$PATH" "HOME=$tmp/home" "GIT_FORGE_LIB=$LIB" GIT_CONFIG_NOSYSTEM=1 \
    SANDBOX_WORKSPACE="$tmp/ws" \
    GITHUB_TOKEN=tok-gh GITLAB_TOKEN=tok-gl \
    GIT_USER_NAME='Test User' GIT_USER_EMAIL='test@example.com' \
    bash "$SETUP" 2>&1)"
setup_rc=$?
check 'setup exit code' '0' "$setup_rc"

cfg="$tmp/home/.gitconfig"
check 'GitHub credential helper 寫進 .gitconfig' 'sandbox-env' \
    "$(HOME=$tmp/home git config --global --get 'credential.https://github.com.helper')"
check 'GitLab credential helper 寫進 .gitconfig' 'sandbox-env' \
    "$(HOME=$tmp/home git config --global --get 'credential.https://gitlab.com.helper')"
check 'SSH remote 改寫規則' 'git@github.com:' \
    "$(HOME=$tmp/home git config --global --get-all 'url.https://github.com/.insteadOf' | head -1)"
check 'safe.directory' "$tmp/ws" \
    "$(HOME=$tmp/home git config --global --get-all safe.directory | head -1)"
check '身分寫入' 'Test User <test@example.com>' \
    "$(HOME=$tmp/home git config --global --get user.name) <$(HOME=$tmp/home git config --global --get user.email)>"

# 禁令 4：token 不落地。這兩條是本任務最重要的斷言。
if grep -qE 'tok-gh|tok-gl' "$cfg"; then
    no 'token 不出現在 .gitconfig' '(無 token)' "$(grep -nE 'tok-gh|tok-gl' "$cfg")"
else
    ok 'token 不出現在 .gitconfig'
fi
check '沒有產生 ~/.git-credentials' 'absent' \
    "$([ -e "$tmp/home/.git-credentials" ] && echo present || echo absent)"
if printf '%s' "$setup_out" | grep -qE 'tok-gh|tok-gl'; then
    no 'token 不出現在啟動輸出' '(只印長度)' "$setup_out"
else
    ok 'token 不出現在啟動輸出'
fi

printf '\n== setup-git-auth + 真的 git：credential fill 端到端 ==\n'
fill="$(printf 'protocol=https\nhost=github.com\n\n' | env "PATH=$tmp/bin:$PATH" \
    "HOME=$tmp/home" "GIT_FORGE_LIB=$LIB" GITHUB_TOKEN=tok-gh \
    git credential fill 2>/dev/null)"
check 'git credential fill 取得 token' \
    'protocol=https
host=github.com
username=x-access-token
password=tok-gh' \
    "$fill"

printf '\n== setup-git-auth：沒有任何 token 時仍要能啟動 ==\n'
mkdir -p "$tmp/home2"
bare_out="$(env -i "PATH=$PATH" "HOME=$tmp/home2" "GIT_FORGE_LIB=$LIB" GIT_CONFIG_NOSYSTEM=1 \
    SANDBOX_WORKSPACE="$tmp/ws" bash "$SETUP" 2>&1)"
bare_rc=$?
check '空環境 exit code' '0' "$bare_rc"
check '空環境會說 GitHub 未設定' 'yes' \
    "$(printf '%s' "$bare_out" | grep -q 'GitHub' && printf '%s' "$bare_out" | grep -q '未設定 token' && echo yes || echo no)"
check '空環境會說身分未設定' 'yes' \
    "$(printf '%s' "$bare_out" | grep -q 'git 身分未設定' && echo yes || echo no)"

printf '\n== setup-git-auth：SANDBOX_GIT_REWRITE_SSH=0 可關掉改寫 ==\n'
mkdir -p "$tmp/home3"
env -i "PATH=$PATH" "HOME=$tmp/home3" "GIT_FORGE_LIB=$LIB" GIT_CONFIG_NOSYSTEM=1 SANDBOX_WORKSPACE="$tmp/ws" \
    GITHUB_TOKEN=tok-gh SANDBOX_GIT_REWRITE_SSH=0 bash "$SETUP" >/dev/null 2>&1
check '關掉後沒有 insteadOf' '' \
    "$(HOME=$tmp/home3 git config --global --get-all 'url.https://github.com/.insteadOf')"

printf '\n== HOME 寫不進去時要大聲失敗，不能默默什麼都沒設 ==\n'
# 用「不存在的路徑」當主要斷言：root 會繞過 chmod 的權限檢查，所以 chmod 500 的
# 目錄對 root 來說仍可寫，那樣的測試以 root 跑會假綠（實測過）。
bad_out="$(env -i "PATH=$PATH" "HOME=$tmp/no-such-home" "GIT_FORGE_LIB=$LIB" \
    GIT_CONFIG_NOSYSTEM=1 SANDBOX_WORKSPACE="$tmp/ws" GITHUB_TOKEN=tok-gh \
    bash "$SETUP" 2>&1)"
bad_rc=$?
# 非 0 才會觸發 entrypoint 的警告；靜默成功是這裡唯一不能接受的結果
check 'HOME 不存在 → exit 非 0' 'nonzero' "$([ "$bad_rc" -ne 0 ] && echo nonzero || echo zero)"
check 'HOME 不存在 → 有講原因' 'yes' \
    "$(printf '%s' "$bad_out" | grep -q 'HOME' && echo yes || echo no)"

# 真正的「存在但不可寫」只有在非 root 身分下才成立
mkdir -p "$tmp/ro"; chmod 500 "$tmp/ro"
if [ "$(id -u)" -eq 0 ] && command -v setpriv >/dev/null 2>&1; then
    ro_rc=0
    setpriv --reuid=65534 --regid=65534 --clear-groups \
        env "PATH=$PATH" "HOME=$tmp/ro" "GIT_FORGE_LIB=$LIB" GIT_CONFIG_NOSYSTEM=1 \
        SANDBOX_WORKSPACE="$tmp/ws" GITHUB_TOKEN=tok-gh bash "$SETUP" >/dev/null 2>&1 || ro_rc=$?
    check 'HOME 不可寫（以 uid 65534）→ exit 非 0' 'nonzero' \
        "$([ "$ro_rc" -ne 0 ] && echo nonzero || echo zero)"
elif [ "$(id -u)" -eq 0 ]; then
    printf '  SKIP 沒有 setpriv，無法以非 root 驗「存在但不可寫」\n'
else
    ro_rc=0
    env "PATH=$PATH" "HOME=$tmp/ro" "GIT_FORGE_LIB=$LIB" GIT_CONFIG_NOSYSTEM=1 \
        SANDBOX_WORKSPACE="$tmp/ws" GITHUB_TOKEN=tok-gh bash "$SETUP" >/dev/null 2>&1 || ro_rc=$?
    check 'HOME 不可寫 → exit 非 0' 'nonzero' \
        "$([ "$ro_rc" -ne 0 ] && echo nonzero || echo zero)"
fi
chmod 700 "$tmp/ro"

printf '\n== glab 整合（有裝才驗）==\n'
if command -v glab >/dev/null 2>&1; then
    mkdir -p "$tmp/home4"
    env -i "PATH=$PATH" "HOME=$tmp/home4" "GIT_FORGE_LIB=$LIB" GIT_CONFIG_NOSYSTEM=1 SANDBOX_WORKSPACE="$tmp/ws" \
        GITLAB_TOKEN=tok-gl GLAB_SEND_TELEMETRY=0 bash "$SETUP" >/dev/null 2>&1
    check 'glab git_protocol 被設成 https' 'https' \
        "$(HOME=$tmp/home4 GLAB_SEND_TELEMETRY=0 glab config get git_protocol 2>/dev/null)"
else
    printf '  SKIP glab 未安裝，跳過 git_protocol 檢查（image 內有裝）\n'
fi

printf '\n通過 %s，失敗 %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
