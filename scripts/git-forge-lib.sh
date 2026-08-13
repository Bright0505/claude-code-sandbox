#!/bin/bash
# Shared reading of the forge (GitHub/GitLab) settings supplied via .env.claude.
#
# Sourced by three places that must agree on "which host, which token":
#   - git-credential-env.sh  (answers git's credential requests)
#   - setup-git-auth.sh      (configures git/glab at container start)
#   - init-firewall.sh       (opens egress to those hosts)
#
# Kept in one file on purpose: a host that the firewall opens but the credential
# helper doesn't recognise (or vice versa) fails in a way that reads like a
# network fault. See docs/DECISIONS.md D5 for why this is abstracted now and not
# earlier - this is the third caller.
#
# Env var names follow the upstream CLIs so a single .env.claude serves both the
# CLIs and git: gh reads GH_TOKEN/GITHUB_TOKEN, glab reads GITLAB_TOKEN and
# GITLAB_HOST (both verified against the shipped tools, 2026-08-13).

# gitlab.example.com | https://gitlab.example.com/ | gitlab.example.com:8443/x
#   -> gitlab.example.com
# Port is stripped because git hands the credential helper "host:port" only for
# non-default ports, and `dig` needs a bare hostname either way.
forge_normalize_host() {
    local h="${1:-}"
    h="${h#*://}"
    h="${h%%/*}"
    printf '%s' "${h%%:*}"
}

forge_github_host() {
    forge_normalize_host "${GITHUB_HOST:-${GH_HOST:-github.com}}"
}

forge_gitlab_host() {
    forge_normalize_host "${GITLAB_HOST:-gitlab.com}"
}

forge_github_token() {
    printf '%s' "${GITHUB_TOKEN:-${GH_TOKEN:-}}"
}

forge_gitlab_token() {
    printf '%s' "${GITLAB_TOKEN:-${GITLAB_ACCESS_TOKEN:-}}"
}

# HTTPS-with-token needs *some* username. These are the documented conventions
# (GitHub: x-access-token, GitLab: oauth2); both are overridable because a wrong
# guess here would otherwise be expensive to work around.
forge_github_user() {
    printf '%s' "${GITHUB_USER:-x-access-token}"
}

forge_gitlab_user() {
    printf '%s' "${GITLAB_USER:-oauth2}"
}
