#!/bin/bash
set -e

# Container starts as root so the firewall can be configured, then drops
# to the unprivileged $USERNAME for everything else (matches Dockerfile.claude).
if [ "$(id -u)" = "0" ]; then
    /usr/local/bin/init-firewall.sh
    exec gosu claude "$@"
fi

exec "$@"
