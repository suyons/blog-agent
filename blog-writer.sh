#!/bin/bash
# blog-writer.sh — daily automated blog drafter.
#
# At 00:05 UTC (via blog-writer.timer) this reads YESTERDAY's (UTC) git diff from
# a private note vault and asks Claude Code, headless, to draft a public Hugo blog
# post on the `draft` branch of the blog repo — following the rules in
# BLOG_GUIDE.md. It NEVER touches the blog's `main` branch.
#
# On a thin day (no commits, or nothing blog-worthy) it writes no post and logs why.
#
# Configuration lives in a gitignored .env file (see .env.example). Run logs stay
# LOCAL ONLY; each run sends a single status message to a Discord webhook.
#
# Usage:
#   blog-writer.sh            # normal run: may commit + push to `draft`
#   blog-writer.sh --dry-run  # write + build-check only, no commit/push
#
# Env overrides (also settable in .env):
#   BLOG_WRITER_MODEL     model id (default: claude-opus-4-8)
#   BLOG_WRITER_DATE      override "today" as YYYY-MM-DD (for testing past days)
#   BLOG_AGENT_ENV        path to the .env file (default: $HOME/blog-agent/.env)
#   BLOG_WRITER_SKIP_NOTIFY  set to 1 to suppress the Discord notification
set -uo pipefail

# ---- load config -----------------------------------------------------------
ENV_FILE="${BLOG_AGENT_ENV:-$HOME/blog-agent/.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a; . "$ENV_FILE"; set +a
fi

NOTE_REPO="${NOTE_REPO:?set NOTE_REPO in $ENV_FILE}"
BLOG_REPO="${BLOG_REPO:?set BLOG_REPO in $ENV_FILE}"
AGENT_DIR="${AGENT_DIR:?set AGENT_DIR in $ENV_FILE}"
GUIDE="$AGENT_DIR/BLOG_GUIDE.md"
LOG_DIR="$AGENT_DIR/logs"
MODEL="${BLOG_WRITER_MODEL:-claude-opus-4-8}"
GITHUB_OWNER="${GITHUB_OWNER:-}"
BLOG_REPO_NAME="${BLOG_REPO_NAME:-}"
MAX_DIFF_BYTES=400000

export PATH="$HOME/.local/bin:/opt/node/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/bin"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

mkdir -p "$LOG_DIR"
TODAY="${BLOG_WRITER_DATE:-$(date -u +%Y-%m-%d)}"
TODAY_COMPACT="${TODAY//-/}"   # yyyymmdd, used as the post filename prefix
YDAY="$(date -u -d "${TODAY} -1 day" +%Y-%m-%d)"
RUN_LOG="$LOG_DIR/${TODAY}.log"
DIFF_FILE="$(mktemp /tmp/note-diff.XXXXXX.txt)"
trap 'rm -f "$DIFF_FILE"' EXIT

log() { echo "[$(date -u +%FT%TZ)] $*" | tee -a "$RUN_LOG"; }

# Minimal JSON string escaper for a single status line (no jq/python dependency).
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/ }"; s="${s//$'\r'/ }"; s="${s//$'\t'/ }"
  printf '"%s"' "$s"
}

notify_discord() {
  local message="$1"
  if [[ -z "${DISCORD_WEBHOOK_URL:-}" ]]; then
    log "no DISCORD_WEBHOOK_URL set — skipping notification"; return
  fi
  if curl -fsS -X POST -H 'Content-Type: application/json' \
        -d "{\"content\": $(json_escape "$message")}" \
        "$DISCORD_WEBHOOK_URL" --max-time 20 >/dev/null 2>&1; then
    log "Discord notified"
  else
    log "WARN: Discord notification failed"
  fi
}

log "================ blog-writer start ================"
log "dry_run=$DRY_RUN  model=$MODEL  today=$TODAY  yesterday=$YDAY"

# ---- 1. compute yesterday's diff from the note vault ----
cd "$NOTE_REPO" || { log "FATAL: note repo $NOTE_REPO missing"; exit 1; }
START="$(git rev-list -1 --before="${YDAY}T00:00:00Z" HEAD 2>/dev/null)"
END="$(git rev-list -1 --before="${TODAY}T00:00:00Z" HEAD 2>/dev/null)"

if [[ -z "$END" ]]; then
  log "SKIP — no commits before ${TODAY}T00:00:00Z; nothing to write."
  exit 0
fi
if [[ "$START" == "$END" ]]; then
  log "SKIP — no commits in window ${YDAY}..${TODAY} (UTC). Quiet day."
  exit 0
fi

EMPTY_TREE="$(git hash-object -t tree /dev/null)"
BASE="${START:-$EMPTY_TREE}"
RANGE_DESC="${START:-<root>}..$END"
{
  echo "### Source: private note vault, window ${YDAY}T00:00:00Z .. ${TODAY}T00:00:00Z (UTC)"
  echo "### Range: $RANGE_DESC"
  echo
  echo "### Commit subjects in window:"
  if [[ -n "$START" ]]; then git log --format='- %cI  %s' "$START..$END"; else git log --format='- %cI  %s' "$END"; fi
  echo
  echo "### Diffstat:"
  git diff --stat "$BASE" "$END"
  echo
  echo "### Full diff:"
  git diff "$BASE" "$END"
} > "$DIFF_FILE" 2>/dev/null

BYTES=$(wc -c < "$DIFF_FILE")
if (( BYTES > MAX_DIFF_BYTES )); then
  log "diff is ${BYTES}B — truncating to ${MAX_DIFF_BYTES}B for context safety"
  head -c "$MAX_DIFF_BYTES" "$DIFF_FILE" > "${DIFF_FILE}.t" \
    && printf '\n\n[... diff truncated at %s bytes ...]\n' "$MAX_DIFF_BYTES" >> "${DIFF_FILE}.t" \
    && mv "${DIFF_FILE}.t" "$DIFF_FILE"
fi
log "diff range $RANGE_DESC, ${BYTES} bytes -> $DIFF_FILE"

# ---- 2. prepare the `draft` branch on the blog repo ----
cd "$BLOG_REPO" || { log "FATAL: blog repo $BLOG_REPO missing"; exit 1; }
if ! git diff --quiet || ! git diff --cached --quiet; then
  log "WARN: blog repo tree not clean — stashing before branch prep"
  git stash push -u -m "blog-writer autostash $TODAY" >/dev/null 2>&1 || true
fi
git fetch --quiet origin || log "WARN: git fetch failed (offline?); using local refs"
if git ls-remote --exit-code --heads origin draft >/dev/null 2>&1; then
  git switch -C draft origin/draft --quiet
  if ! git rebase origin/main --quiet; then
    git rebase --abort 2>/dev/null
    git switch -C draft origin/draft --quiet
    log "WARN: rebasing draft onto main conflicted — kept origin/draft as-is"
  fi
else
  git switch -C draft origin/main --quiet
  log "draft branch did not exist on origin — created from origin/main"
fi
log "on branch '$(git branch --show-current)', base $(git rev-parse --short HEAD)"

# ---- 3. invoke the writer agent ----
read -r -d '' PROMPT <<EOF
You are the daily blog-writing agent for a PUBLIC Hugo blog. Read and follow the
guide at $GUIDE EXACTLY before doing anything — it defines voice, the quality bar,
the frontmatter schema, and the privacy/scrubbing rules.

SOURCE MATERIAL (the ONLY input for today's post(s)): yesterday's edits to a PRIVATE
note vault, captured here:
    $DIFF_FILE
The vault is private and MAY CONTAIN REAL secrets, API keys/tokens, IPs, hostnames,
employer/client names, and personal data. The blog is PUBLIC. Scrub everything per
the guide's Privacy section. If a credential in the diff looks REAL, never reproduce
it and call it out prominently in your summary (it may need rotating).

YOU ARE IN: $BLOG_REPO, already on the 'draft' branch (prepared for you).
- Read 2-3 recent files in content/posts/ to match frontmatter schema and voice.
- Filenames: content/posts/${TODAY_COMPACT}-<slug>.md (shared yyyymmdd date prefix +
  a distinct kebab slug per post). date frontmatter = $TODAY. draft: false.

DECISION — judge blog-worthiness honestly:
- If yesterday's material is thin (typos, trivial edits, half-formed notes, nothing
  that clears the "a sharp engineer bookmarks this" bar), DO NOT write any post.
  Print exactly one line:  BLOG_WRITER: SKIP — <one-line reason>
  then stop. Commit nothing.
- If it IS worthy: write a SEPARATE post for EACH genuinely distinct thread that
  independently clears the bookmark bar. Most days that is exactly ONE post. Write
  more than one ONLY when the material truly supports it — hard cap of 3 per run.
  Quality over volume: never split a single idea across posts to pad the count, never
  promote a thin thread just to fill the cap, and make sure each post stands on its
  own thesis with no overlap with the others or with already-published posts.
  For EACH post: write content/posts/${TODAY_COMPACT}-<slug>.md with its own slug.
  Then build-check everything and commit one post per commit:
      hugo --gc --minify --buildDrafts=false   # run from $BLOG_REPO; fix any error first
      git add content/posts/${TODAY_COMPACT}-<slug>.md   # the post you just wrote
      git commit -m "post: <title>"                       # one commit per post
      git push -u origin draft                            # push once, after all posts
  Never touch main. Commit ONLY post files you created under content/posts/.

FINISH with a summary. For EACH post you wrote, include its own line (one per post):
    BLOG_WRITER: POSTED — <slug>
then, per post: the thesis, every redaction you made (flag any seemingly-REAL
credential), claims the human should fact-check, and any code you wrote but could not
run. If you wrote more than one, say in one line why each thread earned its own post.
EOF

if (( DRY_RUN )); then
  PROMPT="$PROMPT

DRY RUN MODE: do everything EXCEPT 'git commit' and 'git push'. Write the post file,
run the hugo build-check, then print your summary plus the commit message you WOULD
have used. Do not commit. Do not push."
fi

log "invoking claude (headless, $MODEL)…"
claude -p "$PROMPT" \
  --model "$MODEL" \
  --dangerously-skip-permissions \
  --add-dir "$NOTE_REPO" --add-dir "$AGENT_DIR" --add-dir /tmp \
  2>&1 | tee -a "$RUN_LOG"
STATUS=${PIPESTATUS[0]}

log "claude exited with status $STATUS"

# ---- 3.5 ensure an open draft->main PR on the blog repo (one-click merge) ----
# Only when a post actually landed. If a PR is already open it auto-updates with the
# new commit; otherwise create one. Non-fatal: never blocks the run. The PAT is read
# from the git credential store and is NEVER logged.
if (( ! DRY_RUN )) && grep -q "BLOG_WRITER: POSTED" "$RUN_LOG"; then
  if [[ -z "$GITHUB_OWNER" || -z "$BLOG_REPO_NAME" ]]; then
    log "WARN: GITHUB_OWNER/BLOG_REPO_NAME not set — skipped PR creation"
  else
    cd "$BLOG_REPO"
    GH_TOKEN="$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null | sed -n 's/^password=//p')"
    if [[ -n "$GH_TOKEN" ]]; then
      api="https://api.github.com/repos/${GITHUB_OWNER}/${BLOG_REPO_NAME}"
      existing="$(curl -s -H "Authorization: token $GH_TOKEN" \
          "$api/pulls?head=${GITHUB_OWNER}:draft&base=main&state=open" --max-time 20 \
          | grep -m1 '"html_url"' | sed -E 's/.*"(https[^"]+)".*/\1/')"
      if [[ -n "$existing" ]]; then
        log "PR already open (updated with new commit): $existing"
      else
        body="Auto-generated blog drafts from the daily note-diff writer. Review the posts and merge to publish (GitHub Pages deploys on push to main)."
        url="$(curl -s -X POST -H "Authorization: token $GH_TOKEN" "$api/pulls" \
            -d "{\"title\":\"Blog drafts for review\",\"head\":\"draft\",\"base\":\"main\",\"body\":\"$body\"}" \
            --max-time 20 | grep -m1 '"html_url"' | sed -E 's/.*"(https[^"]+)".*/\1/')"
        if [[ -n "$url" ]]; then log "opened PR: $url"; else log "WARN: PR creation returned no url (API error or no diff)"; fi
      fi
    else
      log "WARN: no GitHub token in credential store; skipped PR creation"
    fi
  fi
fi

# ---- 4. notify Discord with the run result (logs stay local) ----
# Set BLOG_WRITER_SKIP_NOTIFY=1 to suppress (e.g. during a backfill, which sends one
# consolidated message at the end instead of one per day).
if (( ! DRY_RUN )) && [[ "${BLOG_WRITER_SKIP_NOTIFY:-0}" != 1 ]]; then
  if   grep -q "BLOG_WRITER: POSTED" "$RUN_LOG"; then RESULT="POSTED"
  elif grep -qE "BLOG_WRITER: SKIP|SKIP —" "$RUN_LOG"; then RESULT="SKIP"
  elif (( STATUS != 0 )); then RESULT="ERROR(exit $STATUS)"
  else RESULT="done"; fi
  if [[ "$RESULT" == "POSTED" ]]; then
    # one POSTED line per post — report the count and join the slugs
    count="$(grep -cE 'BLOG_WRITER: POSTED' "$RUN_LOG")"
    slugs="$(grep -hoE 'BLOG_WRITER: POSTED — .+' "$RUN_LOG" \
             | sed -E 's/^BLOG_WRITER: POSTED — //' | paste -sd '|' - | sed 's/|/, /g')"
    notify_discord "blog-writer ${TODAY}: POSTED ${count} — ${slugs}"
  else
    verdict="$(grep -hoE 'BLOG_WRITER: SKIP[^\n]*' "$RUN_LOG" | tail -1)"
    notify_discord "blog-writer ${TODAY}: ${RESULT}${verdict:+ — ${verdict#BLOG_WRITER: SKIP — }}"
  fi
fi

log "================ blog-writer end ================"
exit "$STATUS"
