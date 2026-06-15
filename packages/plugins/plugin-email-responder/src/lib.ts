/**
 * Pure helpers for the email-responder plugin. No IMAP/Discord/LLM I/O lives here
 * so every function below is unit-testable in isolation. The worker wires these
 * around imapflow + ctx.http + the draft agent.
 */

/** Minimal view of an incoming message the pure layer needs to reason about. */
export interface IncomingMail {
  /** IMAP UID in the source mailbox. */
  uid: number;
  from: string;
  subject: string;
  messageId: string;
  /** Lowercased header name -> raw value, for machine-noise classification. */
  headers: Record<string, string>;
  /** Plain-text body, for the snippet + the draft LLM. */
  body: string;
}

export interface CursorState {
  uidValidity: number;
  lastUid: number;
}

/**
 * Drop obvious machine noise BEFORE spending an LLM call. Ported verbatim (intent)
 * from the proven harness, generalised to header inspection:
 * - Auto-Submitted: auto-*
 * - List-Unsubscribe present (bulk)
 * - Precedence: bulk | list
 * - sender mailer-daemon@ / postmaster@ / no-reply / noreply
 * Everything else is left for the LLM to judge via shouldReply.
 */
export function isMachineNoise(mail: Pick<IncomingMail, "from" | "headers">): boolean {
  const h = mail.headers;
  const autoSubmitted = (h["auto-submitted"] ?? "").trim().toLowerCase();
  if (autoSubmitted.startsWith("auto-")) return true;

  if ((h["list-unsubscribe"] ?? "").trim().length > 0) return true;

  const precedence = (h["precedence"] ?? "").trim().toLowerCase();
  if (precedence === "bulk" || precedence === "list") return true;

  const from = (mail.from ?? "").toLowerCase();
  if (/mailer-daemon@|postmaster@/.test(from)) return true;
  // Anchor no-reply to the address local-part so a display name like
  // "Jean Noreply Tremblay <jean@x.com>" isn't dropped.
  if (/\bno-?reply[^@\s]*@/.test(from)) return true;

  return false;
}

/** Prefix "Re: " exactly once — never produce "Re: Re: …". */
export function singleReSubject(subject: string): string {
  const s = (subject || "(no subject)").trim();
  return /^re:/i.test(s) ? s : `Re: ${s}`;
}

/**
 * Strip CR/LF/tab from a header value so attacker-controlled input — a crafted or
 * RFC2047-encoded Subject/From that decodes to contain newlines — cannot inject
 * extra headers (e.g. a `Bcc:`) into the saved draft.
 */
function sanitizeHeaderValue(value: string): string {
  return value.replace(/[\r\n\t]+/g, " ").trim();
}

/**
 * Build a raw RFC822 reply ready to APPEND to Drafts.
 * - Subject de-duplicated via {@link singleReSubject}
 * - In-Reply-To / References only when we have a source Message-ID
 * - signature appended in code (the LLM never writes it)
 * - every header value is CRLF-sanitized to prevent header injection
 */
export function buildReplyRfc822(args: {
  fromAddress: string;
  incomingFrom: string;
  incomingSubject: string;
  incomingMessageId: string;
  body: string;
  signature: string;
}): string {
  const subject = sanitizeHeaderValue(singleReSubject(args.incomingSubject));
  const fullBody = `${args.body}\n\n${args.signature}\n`;
  const headers = [
    `From: ${sanitizeHeaderValue(args.fromAddress)}`,
    `To: ${sanitizeHeaderValue(args.incomingFrom)}`,
    `Subject: ${subject}`,
  ];
  const mid = sanitizeHeaderValue(args.incomingMessageId);
  if (mid) {
    headers.push(`In-Reply-To: ${mid}`);
    headers.push(`References: ${mid}`);
  }
  headers.push("MIME-Version: 1.0");
  headers.push("Content-Type: text/plain; charset=utf-8");
  return `${headers.join("\r\n")}\r\n\r\n${fullBody.replace(/\n/g, "\r\n")}`;
}

/** Domain of an inbox address, e.g. "contact@pharmia.ca" -> "pharmia.ca". */
export function inboxDomain(address: string): string {
  return address.split("@")[1] ?? "";
}

/**
 * Roundcube compose deep-link for a saved draft. Host is derived from the inbox
 * domain (`mail.<domain>`) — never hardcoded or stored.
 */
export function roundcubeDeepLink(address: string, appendUid: number | string): string {
  const domain = inboxDomain(address);
  return `https://mail.${domain}/?_task=mail&_action=compose&_draft_uid=${encodeURIComponent(String(appendUid))}&_mbox=Drafts`;
}

/**
 * Decide which UIDs to process this tick, UIDVALIDITY-aware and batch-capped.
 *
 * - First run (no stored cursor): seed at the mailbox's current max UID, process
 *   nothing (avoids drafting a reply to the entire historical backlog on install).
 * - UIDVALIDITY changed: the server renumbered UIDs — reset, re-seed at current
 *   max, process nothing this tick, and signal `reset` so the caller can log it.
 * - Steady state: take UIDs strictly greater than `lastUid`, oldest first, capped
 *   at `batchCap` so a backlog drains over successive ticks.
 */
export function selectUidsToProcess(args: {
  stored: CursorState | null;
  mailboxUidValidity: number;
  availableUids: number[];
  batchCap: number;
}): { toProcess: number[]; reset: boolean; seededCursor: CursorState | null } {
  const sorted = [...args.availableUids].sort((a, b) => a - b);
  const maxUid = sorted.length > 0 ? sorted[sorted.length - 1]! : 0;

  const isFirstRun = args.stored === null;
  const validityChanged = args.stored !== null && args.stored.uidValidity !== args.mailboxUidValidity;

  if (isFirstRun || validityChanged) {
    return {
      toProcess: [],
      reset: validityChanged,
      seededCursor: { uidValidity: args.mailboxUidValidity, lastUid: maxUid },
    };
  }

  const lastUid = args.stored!.lastUid;
  const toProcess = sorted.filter((uid) => uid > lastUid).slice(0, Math.max(0, args.batchCap));
  return { toProcess, reset: false, seededCursor: null };
}

/** Clamp a snippet for Discord embed fields (which cap at 1024). */
export function clip(value: string, max: number): string {
  const s = (value || "").trim();
  return s.length > max ? `${s.slice(0, max - 1)}…` : s;
}

/**
 * Discord embed payload for one draft-ready email. Pure builder so it can be
 * asserted in tests; the worker POSTs the result via ctx.http.fetch.
 */
export function buildDiscordEmbed(args: {
  incomingFrom: string;
  incomingSubject: string;
  snippet: string;
  draftSubject: string;
  draftFullBody: string;
  deepLink: string;
}): unknown {
  return {
    allowed_mentions: { parse: [] },
    embeds: [
      {
        title: "📧 Nouveau courriel — brouillon prêt à réviser",
        color: 0x53a329,
        fields: [
          { name: "De", value: clip(args.incomingFrom, 256) || "(inconnu)", inline: true },
          { name: "Sujet (reçu)", value: clip(args.incomingSubject, 256) || "(aucun)", inline: true },
          { name: "Extrait du courriel reçu", value: clip(args.snippet, 300) || "(vide)" },
          { name: "Brouillon — sujet", value: clip(args.draftSubject, 256) },
          { name: "Brouillon — corps (avec signature)", value: clip(args.draftFullBody, 1024) },
        ],
        footer: { text: "Pipeline e-mail Paperclip · brouillon seulement — aucun envoi automatique" },
        timestamp: new Date().toISOString(),
      },
    ],
    components: [
      {
        type: 1,
        components: [{ type: 2, style: 5, label: "Ouvrir le brouillon dans Roundcube", url: args.deepLink }],
      },
    ],
  };
}
