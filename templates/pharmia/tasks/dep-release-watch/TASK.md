---
name: "Dependency & Service Release Watch"
project: "pharmamate"
assignee: "code-health"
recurring: true
description: >
  Fires once per NEW GitHub release of a Pharmia dependency (package.json) or
  self-hosted service (Dokploy), pushed in by the n8n release-watcher webhook.
  Judges that one release — ADOPT / WAIT (premature) / ACT-NOW (security) / FYI —
  with a one-line why and (for WAITs) a recheck date, then posts the verdict to
  Discord. Reports and recommends; never upgrades anything itself.
---

Judge the ONE release in this webhook payload. The n8n watcher (workflow "Dep & Service Release Watch") already did the watching + dedup — you do only the judgment. Do NOT poll feeds or scan for other releases; this routine is single-release by design (one webhook fire = one release).

## Input — the webhook payload (routine variables)

The trigger payload carries one release:
- `repo` (`owner/name`), `sourceKind` (`dep` | `service`), `pkg` (npm name, if a dep)
- `currentVersion` (what Pharmia pins today, may be null for services), `newVersion` (the release tag)
- `ageDays` (days since publish), `prerelease` (bool), `htmlUrl`, `changelog` (release body, may be truncated)

If `changelog` is thin/empty, fetch the full release + recent issues yourself: `gh api repos/{owner}/{name}/releases/tags/{newVersion}` and `gh api "repos/{owner}/{name}/issues?state=open&sort=created&per_page=20"` to read post-release regression signal.

## Steps

1. **Establish blast radius.** For a `dep`: where/how is it used in `~/Documents/PharmaMate`? Is it pinned exact or loose? Is it on a hot path (`@mastra/*`, `@ai-sdk/*`, `better-auth`, `drizzle-orm`/`drizzle-kit`, `react`/`react-dom`, `@tanstack/*`, `@livekit/*`, `vite`, `zod`)? For a `service`: do we auto-deploy its image tag, or pin a digest?
2. **Read the diff that matters.** Changelog → breaking changes, migration notes, security mentions (CVE/GHSA), deprecations. Cross-check breaking changes against OUR actual usage, not in the abstract.
3. **Apply the `@mastra/*` sibling-pin rule.** A lone `@mastra/x` bump out of lockstep with its siblings is itself a WAIT/risk — Mastra packages must move together (see the `docker-lockfile-preflight` skill).
4. **Tier it** (rubric below) and **post to Discord** (single verdict line + a one-paragraph why). For ACT-NOW, also PushNotification.

## Judgment rubric — ADOPT vs WAIT (premature) vs ACT-NOW vs FYI

- **ACT-NOW** — security fix (CVE / GHSA / "security" in notes), a patch fixing a bug we demonstrably hit, or a deprecation with a hard cutoff. Surface the CVE id + affected range.
- **ADOPT** — patch/minor that has AGED past regression risk (`ageDays` ≥ ~10–14, or heavy adoption with no `regression`/`revert` issue spike), addresses something we care about, no breaking change touching our usage. Behind ≥1 minor on a hot-path dep → lean ADOPT.
- **WAIT (premature)** — a `.0.0` major or `.x.0` minor with low `ageDays` (< ~7); a post-release `regression`/`revert` issue spike; `prerelease`/`rc`/`beta`/`alpha`/`canary`; breaking changes with no migration path or that hit our usage; yanked/deprecated; single-maintainer + no CI; peer-dep conflict with a version we pin; a lone `@mastra/*` bump. Give each WAIT a concrete **recheck-after date** (default +14d).
- **FYI** — new but low-stakes (docs, a loosely-pinned dep, a service we don't auto-update).

Always state: `currentVersion → newVersion`, `ageDays`, and the one-line *why this tier*.

## Remediation policy

- **Proactive — fix in-run, no approval (docs/tooling ONLY):** this TASK.md, CLI gaps in `~/.local/bin`. List under **Remediated**.
- **Ask first — propose, do NOT ship:** ANY dependency bump, `package.json`/lockfile edit, or service redeploy. This routine REPORTS. Real bumps go through the branch + `docker-lockfile-preflight` + review path. Put ADOPT/ACT-NOW as a recommendation in the Discord post and stop. NEVER push a branch or edit a manifest from this task.

## Output — Discord, one verdict per fire

Post to the release-watch Discord channel:
- **Line 1:** `[<TIER>] <repo> <currentVersion>→<newVersion> · <ageDays>d` (TIER ∈ ACT-NOW | ADOPT | WAIT | FYI)
- **Line 2:** the why — one sentence (blast radius + the deciding signal). WAIT adds `· recheck <date>`. ACT-NOW adds the CVE/GHSA id.
- **Line 3 (ADOPT/ACT-NOW only):** `Recommend: bump to <newVersion> — <one-line risk>. Route via branch + docker-lockfile-preflight.`

Then PushNotification ONLY for ACT-NOW: `Release ACT-NOW: <repo> <newVersion> — <CVE>`. ADOPT/WAIT/FYI = Discord only, no ping.
