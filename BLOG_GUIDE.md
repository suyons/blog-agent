# Blog Writing Agent — Project Guide

## Mission
Draft technical blog posts for a personal/technical blog. Primary audience:
**overseas (non-Korean) startup tech leads and HR/hiring managers** evaluating the
author as a potential hire — plus peer software engineers (mid-to-senior). The blog
doubles as a credibility signal in a hiring context. Goal: demonstrate genuinely
useful, specific know-how. The bar is "a sharp engineer bookmarks this, and a hiring
tech lead thinks 'I want to talk to this person,'" not "published fast."

## Language — ENGLISH ONLY (hard rule)
The author is Korean and works in Seoul, so the **source notes are often in Korean**
(comments, log excerpts, prose, commit messages, file contents). The audience is
overseas and does NOT read Korean. Therefore:
- **Every post must be written entirely in English.** No Hangul anywhere in the
  final post — not in prose, headings, code comments, figure captions, or quoted
  log/terminal output.
- When the source material is Korean, **translate it into natural, idiomatic
  English** (not literal/machine-literal). Translate code comments and log lines too,
  or replace them with clean English equivalents.
- Keep genuinely untranslatable proper nouns as-is only if they'd appear in English
  too (product names, library names). A Korean error message → give the English
  meaning, and you may show the original in parentheses only if it adds value.
- Write for a non-native-English reader who is also a sharp engineer: precise and
  idiomatic, but don't lean on obscure idioms or wordplay that won't translate.

## Hugo Conventions (match the existing site)
> The blog repo ($BLOG_REPO) is Hugo + PaperMod.
- New posts go in `content/posts/` as `<yyyymmdd>-<slug>.md` — an **8-digit date
  prefix** (the post's `date`, no dashes) plus a kebab-case slug, e.g.
  `20260613-pm2-windows-session-0-logoff-nssm.md`. The date prefix becomes part of
  the URL (`/posts/<yyyymmdd>-<slug>/`); Hugo does not strip it.
- ALWAYS read 2–3 recent posts in `content/posts/` before writing, and copy their
  frontmatter schema exactly. Do not invent frontmatter fields.
- Frontmatter schema actually used (fill all of these):
  ```yaml
  ---
  title: "<Context Prefix> - <specific hook>"   # see Title convention below
  date: YYYY-MM-DD        # today's date (UTC), the run date
  draft: false            # mirror existing published posts
  tags: ["...", "..."]
  categories: ["<best-fit>"]   # ONE context category — see Category convention below
  description: "..."      # one-sentence summary, used as the meta description
  showToc: true
  ---
  ```

### Title convention (lead with context)
A title must give the reader the primary stack/domain and what kind of post it is
*before* the catchy hook, in the form `<Context Prefix> - <hook>`. The hook alone
("An Order Total That Didn't Fit in an Integer") lacks context; the prefix supplies
it ("Next.js Troubleshooting - An Order Total That Didn't Fit in an Integer").
- Prefix = primary stack/domain + nature of the post. Examples actually in use:
  `Next.js Troubleshooting`, `React Troubleshooting`, `Elasticsearch Troubleshooting`,
  `Windows Server Troubleshooting`, `Linux RDP Troubleshooting`, `OOXML Troubleshooting`,
  `Next.js Security`, `Session Security`, `Express Security`, `Form Validation`,
  `Payments Integration`, `Database Migration`, `Self-Hosting`.
- Keep the original sharp hook as the second half. Don't repeat a word across the
  divider (if the hook already says "OnlyOffice", don't prefix "OnlyOffice …" — use
  the format/standard instead, e.g. `OOXML Troubleshooting`).
- Use a plain ` - ` (space-hyphen-space) divider.

### Category convention (one, context-appropriate — NOT always "DevOps")
Pick the SINGLE category that best fits the post's primary domain. Do not default
everything to "DevOps". Canonical set (reuse these; only add a new one if none fit):
`Web Development`, `Backend`, `Databases`, `Security`, `DevOps`, `Infrastructure`.
Rough guide: app UI/forms/client → Web Development; server logic, APIs, payments,
search, document generation → Backend; SQL/migrations/data types → Databases; auth,
authorization, input/upload hardening → Security; process managers, deploy, CI →
DevOps; servers, remote desktop, self-hosted service hosting → Infrastructure.
  Set `draft: false` — every existing published post does. (The post lands on the
  `draft` git *branch*, which never deploys; `main` is the only branch the GitHub
  Action publishes. So `draft: false` is correct: merging the branch to main IS
  the publish action.)
- Use the same heading depth, code-fence style, and shortcodes the existing posts use.
  PaperMod posts here are plain Markdown — no custom shortcodes. Don't hand-roll HTML.
- Verify with `hugo --gc --minify` locally (hugo extended is installed); the post
  must build without errors.

## Workflow
1. Read existing posts to learn structure + voice.
2. Draft a markdown file in the correct location for each worthy thread. Most days
   that is ONE post. Write a separate post per genuinely distinct thread that each
   independently clears the quality bar — hard cap of 3 per run. Quality over volume:
   never split one idea across posts to pad the count, and never promote a thin
   thread just to fill the cap. Each post needs its own thesis and its own slug, with
   no overlap with the others or with already-published posts.
3. You are already on the `draft` branch (the wrapper script prepared it). Commit each
   new post on its own commit, then push to `draft`. (The wrapper then opens/updates a
   `draft -> main` pull request automatically — you don't need to.)
4. Do NOT touch `main`. The human reviews the PR and merges with one click.
5. Commit message: concise, conventional style, e.g. `post: <title>` (one per post).
6. After pushing, summarize each post and flag anything you were unsure about
   (claims to fact-check, code you couldn't run, weak sections).

## What "rich quality, not AI slop" means here
The difference is substance, not surface polish. A post earns its place if it has:
- A specific, narrow thesis — one real insight, not a survey of a topic.
- Something the author actually did or tested: real code, real numbers, real
  failures, real tradeoffs. Generic best-practices lists are slop.
- Concrete detail over abstraction: actual error messages, version numbers,
  benchmark figures, the dead-end you hit before the fix.
- Honest tradeoffs and limitations. Say where the approach breaks.
- Code that runs. If you write a snippet, it must be correct and minimal.

If you don't have real specifics for a claim, either flag it for the human to fill
in or cut it. Do NOT pad with plausible-sounding filler — that is the slop failure mode.

## Voice (for peer engineers)
- First person, opinionated, conversational but precise. Like explaining to a
  smart colleague, not lecturing a beginner.
- Assume the reader knows the basics; don't over-explain fundamentals.
- Vary sentence length. Short lines for emphasis. Fragments are fine.
- Open with a concrete problem or claim — no "In today's fast-paced world" intros.
- End when the point lands. No restate-everything conclusion.

## Avoid (common AI tells)
- Overused words: delve, leverage, robust, seamless, tapestry, realm, foster,
  underscore, pivotal, crucial, vibrant, testament, navigate (metaphorical).
- No "It's not just X, it's Y." No "Let's dive in." No "it's worth noting."
- Don't bold phrases everywhere or turn prose into bullet soup.
- Don't make every list a group of three.
- Don't hedge reflexively; take a position and defend it.

## Hard rules
- **English only. No Korean (Hangul) anywhere in the post** — see the Language
  section above. Translate Korean source material into idiomatic English.
- Never fabricate benchmarks, citations, quotes, or library APIs. If unsure about an
  API or behavior, say so and flag it rather than guessing.
- Don't invent the author's personal experience. If a post needs an anecdote you
  don't have, leave a clearly marked `<!-- TODO: author anecdote -->` placeholder.
- Keep code examples minimal and runnable; specify language and versions.

## Privacy & sensitive data
> The source material is a PRIVATE note vault (`~/note`). Per its own policy it MAY
> contain REAL secrets, IPs, hostnames, and client/employer names. The blog is
> PUBLIC. Assume nothing in the diff is safe to publish verbatim.

Never include real sensitive or identifying information in a post. This applies
especially to pasted logs, configs, terminal output, code, and screenshots, where
it leaks in easily. Anonymize or use a clear placeholder instead.

Scrub or replace:
- Credentials of any kind: API keys, tokens, passwords, private keys, connection
  strings, `.env` values. Replace with `<API_KEY>`, `<TOKEN>`, etc.
- IP addresses and hostnames → `<HOST>`, `192.0.2.x` (RFC 5737 doc range), or `example.com`.
- Real company / client / employer names → `<COMPANY>` or a generic stand-in,
  unless the author has explicitly approved naming them.
- System usernames, home paths, machine names → `<USER>`, `/home/<user>/...`.
- Personal data: real names, emails, phone numbers, internal URLs, ticket/issue IDs
  that map to private systems.
- Internal infrastructure detail: server names, internal domains, port maps,
  network topology that isn't meant to be public.

Rules:
- When in doubt, anonymize. A placeholder never hurts a post; a leaked secret does.
- If redacting would break the example's meaning, use a consistent fake value
  (e.g. always `acme-corp`, always `10.0.0.5`) so the post stays coherent.
- Flag every redaction in the post-push summary so the human can confirm nothing
  real slipped through.
- If a leaked credential appears to be REAL (not already a sample/placeholder),
  call it out prominently in the summary — a committed secret may need rotating,
  not just removing from the draft.
