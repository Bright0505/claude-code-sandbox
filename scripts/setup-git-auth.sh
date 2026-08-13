#!/bin/bash
# Turn the tokens from .env.claude into a working git setup, then say out loud
# what is in effect.
#
# Runs at container start as the unprivileged user (see entrypoint.sh), so
# everything it writes lands in the container-local ~/.gitconfig - never in the
# bind-mounted /workspace and never on the host. Re-running it is safe.
#
# The printing is not decoration: a token that quietly isn't in effect produces
# a credential prompt or a timeout, which reads as "the environment is broken".
# That misdiagnosis has already happened once here for the network overlay -
# see docs/KNOWN-ISSUES.md K-5.
set -uo pipefail

# shellcheck source=./git-forge-lib.sh
if ! . "${GIT_FORGE_LIB:-/usr/local/lib/git-forge-lib.sh}"; then
    printf 'sandbox: ⚠️ 找不到 git-forge-lib.sh，git 認證未設定\n' >&2
    exit 1
fi

CRED_HELPER=sandbox-env   # resolves to /usr/local/bin/git-credential-sandbox-env
WORKSPACE_PATH="${SANDBOX_WORKSPACE:-/workspace}"

# Everything below writes to $HOME/.gitconfig, and every later git command reads
# it from the same place - so a wrong HOME means the setup lands in a file nobody
# reads, i.e. push silently starts asking for a password again.
# gosu clears HOME and re-derives it from the passwd entry (gosu's main.go:
# "clear HOME so that SetupUser will set it"), so this should never fire; it is
# here because that behaviour is upstream's to change, and the failure it would
# cause is invisible at the point where it matters.
if [ ! -w "${HOME:-/nonexistent}" ]; then
    printf 'sandbox: ⚠️ HOME（%s）不存在或不可寫，git 認證無法設定\n' "${HOME:-<未設定>}" >&2
    exit 1
fi

# /workspace is bind-mounted from the host, so its owner uid is the host user's,
# not necessarily 1000. When they differ, git refuses every command in it with
# "detected dubious ownership" - before any token would ever matter.
if ! git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$WORKSPACE_PATH"; then
    git config --global --add safe.directory "$WORKSPACE_PATH"
fi

# $1=label $2=host $3=token $4=username
configure_forge() {
    local label="$1" host="$2" token="$3" user="$4"

    if [ -z "$token" ]; then
        printf 'sandbox: git 認證 %-6s (%s)：未設定 token —— push 會要求帳號密碼\n' \
            "$label" "$host"
        return 1
    fi

    git config --global "credential.https://${host}.helper" "$CRED_HELPER"

    # SSH remotes cannot work here at all: the firewall opens 80/443 only, so
    # port 22 is closed. Rewrite them rather than let `git push` hang.
    if [ "${SANDBOX_GIT_REWRITE_SSH:-1}" != "0" ]; then
        git config --global --unset-all "url.https://${host}/.insteadOf" 2>/dev/null
        git config --global --add "url.https://${host}/.insteadOf" "git@${host}:"
        git config --global --add "url.https://${host}/.insteadOf" "ssh://git@${host}/"
    fi

    # Length only, never the value: enough to spot a truncated paste in the log
    # without putting the secret in the terminal scrollback.
    printf 'sandbox: git 認證 %-6s (%s)：已載入 token（長度 %s，username %s）\n' \
        "$label" "$host" "${#token}" "$user"
}

gitlab_host="$(forge_gitlab_host)"
gitlab_token="$(forge_gitlab_token)"

configure_forge GitHub "$(forge_github_host)" "$(forge_github_token)" "$(forge_github_user)"
configure_forge GitLab "$gitlab_host" "$gitlab_token" "$(forge_gitlab_user)"

# glab defaults git_protocol to ssh, which port 22 being closed makes unusable.
# --global is required: without it glab writes the *repository's* config, and
# outside a repo it prints an error while still exiting 0.
if [ -n "$gitlab_token" ] && command -v glab >/dev/null 2>&1; then
    glab config set --global git_protocol https >/dev/null 2>&1
    if [ "$gitlab_host" != "gitlab.com" ]; then
        printf 'sandbox: glab 對自架站台 (%s) 需在容器內另外執行 glab auth login --hostname %s；git push 不受影響\n' \
            "$gitlab_host" "$gitlab_host"
    fi
fi

if [ -n "${GIT_USER_NAME:-}" ] && [ -n "${GIT_USER_EMAIL:-}" ]; then
    git config --global user.name "$GIT_USER_NAME"
    git config --global user.email "$GIT_USER_EMAIL"
    printf 'sandbox: git 身分：%s <%s>\n' "$GIT_USER_NAME" "$GIT_USER_EMAIL"
elif [ -n "${GIT_USER_NAME:-}${GIT_USER_EMAIL:-}" ]; then
    printf 'sandbox: ⚠️ GIT_USER_NAME 與 GIT_USER_EMAIL 只設了一個，兩個都要設才會生效\n'
else
    printf '%s\n' \
        'sandbox: git 身分未設定 —— commit 會失敗。在 .env.claude 設 GIT_USER_NAME / GIT_USER_EMAIL，' \
        'sandbox: 或單次用 git -c user.name=... -c user.email=... commit（不落地）'
fi

exit 0
