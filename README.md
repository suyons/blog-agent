# blog-agent

Daily automated technical-blog drafter. At **00:05 UTC** a systemd timer reads
**yesterday's** git diff from a private note vault and asks Claude Code, headless, to
draft a public [Hugo](https://gohugo.io) blog post onto the `draft` branch of the
blog repo — following the editorial + privacy rules in
[`BLOG_GUIDE.md`](./BLOG_GUIDE.md). It never touches the blog's `main` branch.

On a thin day (no commits, or nothing that clears the quality bar) it writes no
post and logs why.

## How it works

```
blog-writer.timer  ─(00:05 UTC daily)─▶  blog-writer.service  ─▶  /usr/local/bin/blog-writer.sh
                                                                        │
   1. git diff of the note vault for [yesterday 00:00Z, today 00:00Z)   │
   2. prepare `draft` branch off origin/main in the blog repo           │
   3. claude -p --dangerously-skip-permissions  (model: opus 4.8)       │
        └─ reads BLOG_GUIDE.md + the diff, judges blog-worthiness,
           writes content/posts/<slug>.md, build-checks with hugo,
           commits `post: <title>`, pushes to `draft`                    │
   4. ensure an open `draft -> main` PR, then send one Discord message   │
```

The human reviews the **`draft -> main` pull request** and merges with one click;
the blog's GitHub Action publishes only on push to `main`. One PR accumulates every
draft until it's merged (then the next post opens a fresh PR). The PR is created via
the GitHub REST API using a PAT read from the local git credential store — no `gh`
needed, and the token is never written to disk or logged.

## Files

| Path | Purpose |
|---|---|
| `blog-writer.sh` | Orchestrator. Installed to `/usr/local/bin/blog-writer.sh`. |
| `backfill.sh` | One-off helper to draft posts across a past date range. |
| `BLOG_GUIDE.md` | Editorial voice, quality bar, frontmatter schema, privacy/scrub rules. |
| `systemd/blog-writer.{service,timer}` | The schedule. Installed to `/etc/systemd/system/`. |
| `install.sh` | Renders the unit for the current user, deploys, enables the timer (idempotent). |
| `.env.example` | Config template — copy to `.env` (gitignored) and fill in. |
| `logs/` | Per-day run logs. **Local only** (gitignored); see Privacy below. |

## Setup

```bash
cp .env.example .env      # then edit .env: paths, GitHub owner, Discord webhook
./install.sh
```

## Config (`.env`)

| Var | Meaning |
|---|---|
| `DISCORD_WEBHOOK_URL` | Webhook that receives one status message per run. Blank disables it. |
| `NOTE_REPO` | Private note vault (git repo) to read yesterday's diff from. |
| `BLOG_REPO` | Local checkout of the public Hugo blog repo. |
| `AGENT_DIR` | This agent's checkout (where `logs/` and `BLOG_GUIDE.md` live). |
| `GITHUB_OWNER` / `BLOG_REPO_NAME` | Used to open the `draft -> main` PR via the REST API. |
| `BLOG_WRITER_MODEL` | Model id (default `claude-opus-4-8`; `claude-sonnet-4-6` is cheaper). |

`BLOG_WRITER_DATE` (env, not in `.env`) overrides "today" to re-run a past day.

## Test without publishing

```bash
# write + hugo build-check only; no commit, no push, no notification
BLOG_WRITER_DATE=2026-06-12 blog-writer.sh --dry-run
```

## Host assumptions

- A private note vault (git) and a public Hugo blog repo (PaperMod theme; `main`
  auto-deploys via a GitHub Pages Action), both checked out locally.
- `hugo` extended and the `claude` CLI on PATH; Claude authenticated under the
  service user's `$HOME`.
- A systemd-based host; the timer runs as your normal user.

## Privacy

The source vault is private and may contain real credentials, IPs, hostnames, and
client/employer names. `BLOG_GUIDE.md` requires scrubbing all of it before anything
reaches a public post, and every run's summary lists the redactions it made and
flags any credential that looked real.

**Run logs never leave the host.** Each log captures the raw note diff and the
agent's redaction summary, so it can contain real secrets — `logs/` is gitignored
and is never committed or pushed. Run status is reported only as a short one-line
message over the Discord webhook (status + post slug or skip reason), which carries
no diff content. Keep your `.env` (and the note vault) private.
