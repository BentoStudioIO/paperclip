# Email Responder (`email-responder`)

First-party Paperclip plugin that watches the shared `contact@` inboxes over IMAP
and **drafts** replies in one professional voice for a human to review and send.

**Draft-only by construction.** There is no SMTP/send code anywhere in this plugin.
Every reply is saved to the inbox's `Drafts` folder with the `\Draft` flag and
announced in Discord with a Roundcube deep-link; a human opens, edits, and sends.

## How it works

A single scheduled job, `poll-inboxes` (cron `*/1 * * * *`), runs in the
control-plane container (local `fork`). Per tick, for each configured inbox:

1. Resolve the inbox IMAP password + Discord bot token from saved secrets.
2. IMAP-connect to Stalwart, open `INBOX`, fetch messages with UID greater than
   the stored cursor (envelope + headers + source in one locked pass).
3. Drop machine noise (`Auto-Submitted: auto-*`, `List-Unsubscribe`,
   `Precedence: bulk/list`, `mailer-daemon@`/`postmaster@`/`no-reply`).
4. For up to `batchCapPerRun` newest messages: ask the gateway (schema-enforced
   `json_schema` structured output) whether to reply and for the body.
5. Append the per-inbox signature **in code**, `APPEND` the RFC822 reply to
   `Drafts` with `\Draft`, post a Discord review embed with the deep-link,
   advance the cursor.

The cursor is per-inbox, UIDVALIDITY-aware (scope `company` / namespace
`<inbox address>` / key `cursor`). On first run or a UIDVALIDITY change it seeds
at the current max UID and processes nothing, so installing never replies to the
historical backlog.

## Architecture

- `src/lib.ts` — pure logic (noise filter, `Re:` de-dup, RFC822 assembly,
  `mail.<domain>` deep-link, cursor advance + UIDVALIDITY reset, batch cap,
  Discord embed builder). Unit-tested in `tests/lib.spec.ts`.
- `src/draft-agent.ts` — schema-enforced draft call via
  `@anthropic-ai/claude-agent-sdk` (no tools, no creds; inherits
  `ANTHROPIC_BASE_URL` / `CLAUDE_CODE_OAUTH_TOKEN` from the server env).
- `src/worker.ts` — wires imapflow + `ctx.http` + the draft agent around the
  pure layer; registers the `poll-inboxes` job.

## Build / test

```bash
pnpm --filter @paperclipai/plugin-email-responder build   # → dist/worker.js, dist/manifest.js
pnpm --filter @paperclipai/plugin-email-responder test    # vitest, pure-logic units
```

The worker is bundled with esbuild; `imapflow` and the Anthropic SDK are bundled
into `dist/worker.js`. A `createRequire` banner is injected so imapflow's dynamic
`require()` of Node built-ins resolves in the ESM output.

## Configuration

`instanceConfigSchema` fields: `inboxes[]` (`address`, `passwordRef` (secret-ref),
`signature`), `discordBotTokenRef` (secret-ref), `discordChannelId`, `imapHost`,
`imapPort`, `model`, `batchCapPerRun`. The deep-link host is derived in code as
`mail.<domain>` — it is never configured or stored.
