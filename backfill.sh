#!/bin/bash
# One-off backfill: write one post per note-activity day over a date range.
# For each window-day D in [START_DAY, END_DAY], runs blog-writer for post-date D+1
# (its diff window is exactly day D). Suppresses the per-run Discord ping and sends
# ONE consolidated summary at the end. Run logs stay local (gitignored).
set -uo pipefail

START_DAY="2026-05-26"
END_DAY="2026-06-12"

ENV_FILE="${BLOG_AGENT_ENV:-$HOME/blog-agent/.env}"
[[ -f "$ENV_FILE" ]] && { set -a; . "$ENV_FILE"; set +a; }
AGENT_DIR="${AGENT_DIR:?set AGENT_DIR in $ENV_FILE}"

export PATH="$HOME/.local/bin:/opt/node/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin"
MASTER="$AGENT_DIR/logs/backfill-$(date -u +%Y%m%dT%H%M%SZ).log"
mkdir -p "$AGENT_DIR/logs"
mlog(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$MASTER"; }

summary=""
mlog "==== BACKFILL start: window-days $START_DAY .. $END_DAY ===="
d="$START_DAY"
while [[ "$d" < "$END_DAY" || "$d" == "$END_DAY" ]]; do
  postdate="$(date -u -d "$d +1 day" +%F)"
  mlog "---- window-day $d  (post date $postdate) ----"
  BLOG_WRITER_SKIP_NOTIFY=1 BLOG_WRITER_DATE="$postdate" \
      /usr/local/bin/blog-writer.sh >>"$MASTER" 2>&1
  # capture the one-line verdict for the consolidated summary
  rl="$AGENT_DIR/logs/${postdate}.log"
  v="$(grep -hoE 'BLOG_WRITER: (POSTED|SKIP)[^\n]*' "$rl" 2>/dev/null | paste -sd '|' - | sed 's/|/; /g')"
  mlog "   verdict: ${v:-<none / see day log>}"
  summary+="${postdate}: ${v:-<none>}"$'\n'
  d="$(date -u -d "$d +1 day" +%F)"
done
mlog "==== BACKFILL done ===="

# one consolidated Discord notification
if [[ -n "${DISCORD_WEBHOOK_URL:-}" ]]; then
  esc=${summary//\\/\\\\}; esc=${esc//\"/\\\"}; esc=${esc//$'\n'/\\n}
  if curl -fsS -X POST -H 'Content-Type: application/json' \
        -d "{\"content\": \"backfill $START_DAY..$END_DAY\\n$esc\"}" \
        "$DISCORD_WEBHOOK_URL" --max-time 20 >/dev/null 2>&1; then
    mlog "Discord notified (consolidated backfill summary)"
  else
    mlog "WARN: Discord notification failed"
  fi
fi
mlog "MASTER LOG: $MASTER"
