/**
 * Draft-only agent. Structured output via a FORCED tool on the gateway's Anthropic
 * Messages API (POST $ANTHROPIC_BASE_URL/v1/messages), using the base @anthropic-ai/sdk
 * — a pure HTTP client. We deliberately do NOT use @anthropic-ai/claude-agent-sdk:
 * its query() spawns the Claude Code CLI binary, which the control-plane container
 * doesn't ship. The worker inherits ANTHROPIC_BASE_URL / CLAUDE_CODE_OAUTH_TOKEN from
 * the server environment. No send path — this only decides + writes a body.
 */
import Anthropic from "@anthropic-ai/sdk";
import { DRAFT_SCHEMA, VOICE_SYSTEM_PROMPT } from "./constants.js";

export interface DraftDecision {
  shouldReply: boolean;
  reason: string;
  draft?: { subject: string; body: string };
}

export interface IncomingEmailForDraft {
  inboxAddress: string;
  from: string;
  subject: string;
  date: string;
  body: string;
}

const DRAFT_TOOL_NAME = "submit_draft";

export interface DraftOptions {
  model: string;
  /** Gateway base URL, e.g. https://llm.bentostudio.io */
  baseUrl: string;
  /**
   * Gateway token. The worker resolves it from a Paperclip secret and passes it in
   * — we do NOT read host env here: the plugin worker runs with a sandboxed env
   * (PATH/NODE_PATH/NODE_ENV/TZ only), so the ANTHROPIC and CLAUDE vars are absent.
   */
  token: string;
}

/**
 * Ask the gateway whether to reply and, if so, for the reply body. Forces a single
 * tool call whose input_schema is DRAFT_SCHEMA, so the output is schema-shaped.
 * Returns shouldReply:false (never throws) on any failure so the worker logs + skips
 * and advances the cursor instead of wedging on the message.
 */
export async function draftReply(email: IncomingEmailForDraft, opts: DraftOptions): Promise<DraftDecision> {
  const prompt = [
    `Incoming email to ${email.inboxAddress}:`,
    `From: ${email.from}`,
    `Subject: ${email.subject}`,
    `Date: ${email.date}`,
    "",
    "Body:",
    email.body,
  ].join("\n");

  try {
    // apiKey -> x-api-key header; the gateway (LiteLLM) accepts it. maxRetries rides
    // out transient 429s (the subscription rate-window is shared across all agents).
    const client = new Anthropic({ baseURL: opts.baseUrl, apiKey: opts.token, maxRetries: 4 });
    const resp = await client.messages.create({
      model: opts.model,
      max_tokens: 2000,
      system: VOICE_SYSTEM_PROMPT,
      messages: [{ role: "user", content: prompt }],
      tools: [
        {
          name: DRAFT_TOOL_NAME,
          description: "Record the drafting decision and, when replying, the reply subject and body.",
          input_schema: DRAFT_SCHEMA as unknown as Anthropic.Tool.InputSchema,
        },
      ],
      tool_choice: { type: "tool", name: DRAFT_TOOL_NAME },
    });

    const toolUse = resp.content.find((block) => block.type === "tool_use");
    if (!toolUse || toolUse.type !== "tool_use") {
      return { shouldReply: false, reason: "model returned no tool output" };
    }
    const out = toolUse.input as Partial<DraftDecision>;
    if (typeof out.shouldReply !== "boolean") {
      return { shouldReply: false, reason: "tool output missing shouldReply" };
    }
    return { shouldReply: out.shouldReply, reason: out.reason ?? "", draft: out.draft };
  } catch (err) {
    return {
      shouldReply: false,
      reason: `gateway error: ${err instanceof Error ? err.message : String(err)}`,
    };
  }
}
