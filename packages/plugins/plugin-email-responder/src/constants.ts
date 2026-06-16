export const PLUGIN_ID = "email-responder";
export const PLUGIN_VERSION = "0.1.0";

export const JOB_KEY_POLL = "poll-inboxes";

/** Folder we APPEND drafts into. */
export const DRAFTS_FOLDER = "Drafts";

/** Per-inbox state lives under (company / <inbox address> / "cursor"). */
export const CURSOR_STATE_KEY = "cursor";

export const DEFAULT_CONFIG = {
  discordChannelId: "1515177543207096332",
  imapHost: "stalwart.bentostudio.io",
  imapPort: 993,
  model: "gpt-5.5",
  batchCapPerRun: 5,
  gatewayBaseUrl: "https://llm.bentostudio.io",
} as const;

/**
 * Structured-output schema for the draft decision. Enforced by the gateway via
 * `outputFormat: { type: "json_schema" }` — not coaxed from free text.
 */
export const DRAFT_SCHEMA = {
  type: "object",
  properties: {
    shouldReply: { type: "boolean" },
    reason: { type: "string" },
    draft: {
      type: "object",
      properties: {
        subject: { type: "string" },
        body: { type: "string" },
      },
      required: ["subject", "body"],
    },
  },
  required: ["shouldReply", "reason"],
} as const;

/** Single professional voice for the contact@ inbox. Ported verbatim from the proven harness. */
export const VOICE_SYSTEM_PROMPT = `You draft email replies for Bento Studio's contact@ inbox in one professional voice. You receive one incoming email; decide whether a human-worthy reply is warranted and, if so, write the reply body. You never send — a human reviews and sends.
VOICE — professional, warm, concise:
• Mirror the sender's language. Default Québécois French ("Bonjour {first_name},", accents intact); English only if they wrote in English.
• Greeting on its own line, short structured body, a forward-looking closing line ("Au plaisir d'échanger," / "N'hésitez pas si vous avez des questions.").
• No emoji, no "Cher/Monsieur", no legal footer. Use links given in the email/context verbatim; never invent one.
• End at the closing line — do not write a signature; it's appended automatically.
Set shouldReply=false with a brief reason for machine noise, pure FYI, or anything you can't responsibly draft. Otherwise write the draft.`;
