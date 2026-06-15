import { ImapFlow } from "imapflow";
import {
  definePlugin,
  runWorker,
  type PaperclipPlugin,
  type PluginContext,
  type PluginJobContext,
} from "@paperclipai/plugin-sdk";
import {
  CURSOR_STATE_KEY,
  DEFAULT_CONFIG,
  DRAFTS_FOLDER,
  JOB_KEY_POLL,
} from "./constants.js";
import { draftReply } from "./draft-agent.js";
import {
  buildDiscordEmbed,
  buildReplyRfc822,
  isMachineNoise,
  roundcubeDeepLink,
  selectUidsToProcess,
  singleReSubject,
  type CursorState,
  type IncomingMail,
} from "./lib.js";

interface InboxConfig {
  address: string;
  passwordRef: string;
  signature: string;
}

interface ResolvedConfig {
  inboxes: InboxConfig[];
  discordBotTokenRef: string;
  discordChannelId: string;
  imapHost: string;
  imapPort: number;
  model: string;
  batchCapPerRun: number;
}

let currentContext: PluginContext | null = null;

async function getConfig(ctx: PluginContext): Promise<ResolvedConfig> {
  const raw = (await ctx.config.get()) as Partial<ResolvedConfig>;
  return {
    inboxes: Array.isArray(raw.inboxes) ? raw.inboxes : [],
    discordBotTokenRef: raw.discordBotTokenRef ?? "",
    discordChannelId: raw.discordChannelId ?? DEFAULT_CONFIG.discordChannelId,
    imapHost: raw.imapHost ?? DEFAULT_CONFIG.imapHost,
    imapPort: raw.imapPort ?? DEFAULT_CONFIG.imapPort,
    model: raw.model ?? DEFAULT_CONFIG.model,
    batchCapPerRun: typeof raw.batchCapPerRun === "number" ? raw.batchCapPerRun : DEFAULT_CONFIG.batchCapPerRun,
  };
}

function firstHeader(headers: Map<string, string[] | string> | undefined, name: string): string {
  if (!headers) return "";
  const v = headers.get(name);
  if (Array.isArray(v)) return v[0] ?? "";
  return v ?? "";
}

/** Resolve the IMAP password for one inbox and build a connected client. */
async function connectInbox(ctx: PluginContext, cfg: ResolvedConfig, inbox: InboxConfig): Promise<ImapFlow> {
  const pass = await ctx.secrets.resolve(inbox.passwordRef);
  const client = new ImapFlow({
    host: cfg.imapHost,
    port: cfg.imapPort,
    secure: true,
    auth: { user: inbox.address, pass },
    logger: false,
  });
  await client.connect();
  return client;
}

/** Read the stored per-inbox cursor (scope: company / <inbox address> / "cursor"). */
async function readCursor(ctx: PluginContext, address: string): Promise<CursorState | null> {
  const value = await ctx.state.get({
    scopeKind: "company",
    namespace: address,
    stateKey: CURSOR_STATE_KEY,
  });
  if (value && typeof value === "object" && "uidValidity" in value && "lastUid" in value) {
    return value as CursorState;
  }
  return null;
}

async function writeCursor(ctx: PluginContext, address: string, cursor: CursorState): Promise<void> {
  await ctx.state.set({ scopeKind: "company", namespace: address, stateKey: CURSOR_STATE_KEY }, cursor);
}

/**
 * Fetch every incoming-mail view the pipeline needs in a single UID-range pass:
 * envelope (subject/from), the headers the noise filter + threading need, and the
 * raw source (for the plain-text body). Doing it in one pass means all IMAP reads
 * happen while INBOX is locked; the slow LLM/Discord/append work runs after.
 */
async function fetchIncoming(client: ImapFlow, lastUid: number): Promise<IncomingMail[]> {
  const out: IncomingMail[] = [];
  // imapflow treats `<n>:*` as inclusive, so start at lastUid+1.
  // selectUidsToProcess re-filters defensively (> lastUid).
  const range = `${lastUid + 1}:*`;
  for await (const msg of client.fetch(
    range,
    {
      uid: true,
      envelope: true,
      source: true,
      headers: ["message-id", "from", "reply-to", "subject", "date", "auto-submitted", "list-unsubscribe", "precedence"],
    },
    { uid: true },
  )) {
    const headerMap = msg.headers ? parseHeaderLines(msg.headers.toString()) : {};
    const envFrom = msg.envelope?.from?.[0]?.address ?? "";
    const replyTo = headerMap["reply-to"] ?? "";
    out.push({
      uid: Number(msg.uid),
      from: replyTo || headerMap["from"] || envFrom,
      subject: msg.envelope?.subject ?? headerMap["subject"] ?? "",
      messageId: headerMap["message-id"] ?? (msg.envelope?.messageId ?? ""),
      headers: headerMap,
      body: msg.source ? extractPlainText(msg.source.toString()) : "",
    });
  }
  return out;
}

/** Parse a raw header block into a lowercased-name -> value map (first wins). */
function parseHeaderLines(block: string): Record<string, string> {
  const map: Record<string, string> = {};
  for (const line of block.split(/\r?\n/)) {
    const m = line.match(/^([A-Za-z-]+):\s?(.*)$/);
    if (m && !(m[1]!.toLowerCase() in map)) map[m[1]!.toLowerCase()] = m[2]!.trim();
  }
  return map;
}

/** Crude text/plain extraction from a raw RFC822 source (good enough for snippet + LLM). */
function extractPlainText(raw: string): string {
  const sepIndex = raw.search(/\r?\n\r?\n/);
  const body = sepIndex >= 0 ? raw.slice(sepIndex).trim() : raw;
  return body.replace(/=\r?\n/g, "").trim();
}

async function postDiscord(
  ctx: PluginContext,
  cfg: ResolvedConfig,
  botToken: string,
  payload: unknown,
): Promise<void> {
  const res = await ctx.http.fetch(
    `https://discord.com/api/v10/channels/${cfg.discordChannelId}/messages`,
    {
      method: "POST",
      headers: { Authorization: `Bot ${botToken}`, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    },
  );
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Discord ${res.status}: ${text.slice(0, 300)}`);
  }
}

async function processInbox(ctx: PluginContext, cfg: ResolvedConfig, inbox: InboxConfig): Promise<void> {
  const botToken = await ctx.secrets.resolve(cfg.discordBotTokenRef);
  const client = await connectInbox(ctx, cfg, inbox);
  try {
    const lock = await client.getMailboxLock("INBOX");
    let toProcess: number[] = [];
    let incoming: IncomingMail[] = [];
    let seedCursor: CursorState | null = null;
    let uidValidity = 0;
    try {
      uidValidity = Number(client.mailbox && typeof client.mailbox === "object" ? client.mailbox.uidValidity : 0);
      const stored = await readCursor(ctx, inbox.address);
      // Single locked pass: fetch envelope + headers + body for everything past
      // the cursor, so all IMAP reads complete before the lock is released.
      incoming = await fetchIncoming(client, stored?.lastUid ?? 0);
      const decision = selectUidsToProcess({
        stored,
        mailboxUidValidity: uidValidity,
        availableUids: incoming.map((m) => m.uid),
        batchCap: cfg.batchCapPerRun,
      });
      toProcess = decision.toProcess;
      seedCursor = decision.seededCursor;
      if (decision.reset) {
        ctx.logger.warn("UIDVALIDITY changed; cursor reset", { inbox: inbox.address, uidValidity });
      }
    } finally {
      lock.release();
    }

    // First run / reset: seed and process nothing this tick.
    if (seedCursor) {
      await writeCursor(ctx, inbox.address, seedCursor);
      ctx.logger.info("Seeded inbox cursor", { inbox: inbox.address, lastUid: seedCursor.lastUid });
      return;
    }

    if (toProcess.length === 0) return;
    const byUid = new Map(incoming.map((m) => [m.uid, m]));

    for (const uid of toProcess) {
      const mail = byUid.get(uid);
      if (!mail) continue;

      if (isMachineNoise(mail)) {
        ctx.logger.info("Skipped machine noise", { inbox: inbox.address, uid, from: mail.from });
        await writeCursor(ctx, inbox.address, { uidValidity, lastUid: uid });
        continue;
      }

      const decision = await draftReply(
        { inboxAddress: inbox.address, from: mail.from, subject: mail.subject, date: mail.headers["date"] ?? "", body: mail.body },
        cfg.model,
      );

      if (!decision.shouldReply || !decision.draft) {
        ctx.logger.info("No draft produced", { inbox: inbox.address, uid, reason: decision.reason });
        await writeCursor(ctx, inbox.address, { uidValidity, lastUid: uid });
        continue;
      }

      const raw = buildReplyRfc822({
        fromAddress: inbox.address,
        incomingFrom: mail.from,
        incomingSubject: mail.subject,
        incomingMessageId: mail.messageId,
        body: decision.draft.body,
        signature: inbox.signature,
      });

      // APPEND targets Drafts; it does not require INBOX to be the locked mailbox.
      const appended = await client.append(DRAFTS_FOLDER, raw, ["\\Draft"]);
      const appendUid = appended && typeof appended === "object" ? appended.uid : undefined;
      const fullBody = `${decision.draft.body}\n\n${inbox.signature}\n`;
      const embed = buildDiscordEmbed({
        incomingFrom: mail.from,
        incomingSubject: mail.subject,
        snippet: mail.body,
        draftSubject: singleReSubject(mail.subject),
        draftFullBody: fullBody,
        deepLink: roundcubeDeepLink(inbox.address, appendUid ?? ""),
      });
      await postDiscord(ctx, cfg, botToken, embed);

      ctx.logger.info("Drafted reply", { inbox: inbox.address, uid, appendUid });
      await writeCursor(ctx, inbox.address, { uidValidity, lastUid: uid });
    }
  } finally {
    await client.logout().catch(() => {});
  }
}

async function pollInboxes(ctx: PluginContext): Promise<void> {
  const cfg = await getConfig(ctx);
  if (cfg.inboxes.length === 0) {
    ctx.logger.warn("No inboxes configured; nothing to poll");
    return;
  }
  for (const inbox of cfg.inboxes) {
    try {
      await processInbox(ctx, cfg, inbox);
    } catch (error) {
      ctx.logger.error("Inbox poll failed", {
        inbox: inbox.address,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
}

const plugin: PaperclipPlugin = definePlugin({
  async setup(ctx) {
    currentContext = ctx;
    ctx.jobs.register(JOB_KEY_POLL, async (_job: PluginJobContext) => {
      await pollInboxes(ctx);
    });
    ctx.logger.info("Email Responder ready");
  },

  async onHealth() {
    const ctx = currentContext;
    const cfg = ctx ? await getConfig(ctx) : null;
    return {
      status: "ok" as const,
      message: "Email Responder ready",
      details: { inboxes: cfg?.inboxes.map((i) => i.address) ?? [] },
    };
  },
});

export default plugin;
runWorker(plugin, import.meta.url);
