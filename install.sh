#!/bin/bash
# install.sh — deploy the blog-writer agent on this host (run as your normal user).
# Idempotent: re-run after editing blog-writer.sh or the units to redeploy.
# Renders the systemd unit for the invoking user (no hardcoded usernames committed).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

if [[ ! -f "$HERE/.env" ]]; then
  echo "WARNING: $HERE/.env not found. Copy the template and fill it in:"
  echo "    cp '$HERE/.env.example' '$HERE/.env'"
fi

sudo install -m 755 "$HERE/blog-writer.sh" /usr/local/bin/blog-writer.sh

RENDERED="$(mktemp)"
trap 'rm -f "$RENDERED"' EXIT
sed -e "s|__USER__|$USER|g" -e "s|__HOME__|$HOME|g" \
    "$HERE/systemd/blog-writer.service" > "$RENDERED"
sudo install -m 644 "$RENDERED" /etc/systemd/system/blog-writer.service
sudo install -m 644 "$HERE/systemd/blog-writer.timer" /etc/systemd/system/blog-writer.timer
mkdir -p "$HERE/logs"

sudo systemctl daemon-reload
sudo systemctl enable --now blog-writer.timer
echo "deployed. next run:"
systemctl list-timers blog-writer.timer --no-pager
