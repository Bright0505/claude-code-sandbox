#!/bin/bash
# git credential helper - answers `get` from the tokens in the environment.
#
# Installed as /usr/local/bin/git-credential-sandbox-env, so git reaches it as
# `credential.helper = sandbox-env` (git prepends "git-credential-").
#
# Why a helper instead of the usual `store`/`~/.git-credentials`: this way the
# token exists only in the container's process environment. Nothing is written to
# disk, so it cannot end up in a commit, in the bind-mounted /workspace, or in
# the host's project directory. See 禁令 4 in CLAUDE.md.
set -uo pipefail

# shellcheck source=./git-forge-lib.sh
if ! . "${GIT_FORGE_LIB:-/usr/local/lib/git-forge-lib.sh}" 2>/dev/null; then
    printf 'git-credential-sandbox-env: 找不到 git-forge-lib.sh，無法提供憑證\n' >&2
    exit 0   # exit 0: let git fall through to asking, rather than aborting the push
fi

# store/erase have nothing to do: there is no store to write to.
[ "${1:-}" = "get" ] || exit 0

host=""
protocol=""
while IFS= read -r line; do
    [ -z "$line" ] && break
    case "$line" in
        host=*) host="${line#host=}" ;;
        protocol=*) protocol="${line#protocol=}" ;;
    esac
done

# Only HTTPS: the firewall opens 80/443 only, and a token must never travel
# over plain http.
[ "$protocol" = "https" ] || exit 0

host="$(forge_normalize_host "$host")"
github_host="$(forge_github_host)"
gitlab_host="$(forge_gitlab_host)"

case "$host" in
    "$github_host")
        token="$(forge_github_token)"
        user="$(forge_github_user)"
        ;;
    "$gitlab_host")
        token="$(forge_gitlab_token)"
        user="$(forge_gitlab_user)"
        ;;
    *)
        exit 0
        ;;
esac

# No token for this host: stay silent so git's other helpers / the prompt still
# get their turn.
[ -n "$token" ] || exit 0

printf 'username=%s\npassword=%s\n' "$user" "$token"
