/**
 * Draft-only agent: schema-enforced structured output, NO tools, NO creds in code.
 * Ported from the proven agents-VPS harness (draft-agent.mjs). The worker inherits
 * ANTHROPIC_BASE_URL / CLAUDE_CODE_OAUTH_TOKEN from the server environment — this
 * module sets neither. There is no send path; it only decides + writes a body.
 */
import { query } from "@anthropic-ai/claude-agent-sdk";
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

/**
 * Ask the gateway whether to reply and, if so, for the reply body.
 * Returns `shouldReply: false` (never throws) on any structured-output failure so
 * the worker can log + skip without aborting the rest of the batch.
 */
export async function draftReply(email: IncomingEmailForDraft, model: string): Promise<DraftDecision> {
  const prompt = [
    `Incoming email to ${email.inboxAddress}:`,
    `From: ${email.from}`,
    `Subject: ${email.subject}`,
    `Date: ${email.date}`,
    "",
    "Body:",
    email.body,
  ].join("\n");

  const run = query({
    prompt,
    options: {
      allowedTools: [],
      systemPrompt: VOICE_SYSTEM_PROMPT,
      outputFormat: { type: "json_schema", schema: DRAFT_SCHEMA },
      model,
    },
  });

  let result: Record<string, unknown> | null = null;
  for await (const message of run as AsyncIterable<Record<string, unknown>>) {
    if (message.type === "result") result = message;
  }

  if (!result) {
    return { shouldReply: false, reason: "no result message from agent" };
  }
  if (result.subtype === "error_max_structured_output_retries") {
    return { shouldReply: false, reason: "agent could not produce schema-valid output" };
  }
  if (result.subtype !== "success" || !result.structured_output) {
    return { shouldReply: false, reason: `agent error: ${String(result.subtype)}` };
  }

  return result.structured_output as DraftDecision;
}
