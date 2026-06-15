import type { PaperclipPluginManifestV1 } from "@paperclipai/plugin-sdk";
import { DEFAULT_CONFIG, JOB_KEY_POLL, PLUGIN_ID, PLUGIN_VERSION } from "./constants.js";

const manifest: PaperclipPluginManifestV1 = {
  id: PLUGIN_ID,
  apiVersion: 1,
  version: PLUGIN_VERSION,
  displayName: "Email Responder",
  description:
    "Watches the shared contact@ inboxes over IMAP and drafts replies in one professional voice. Draft-only — every reply is saved to Drafts and posted to Discord for a human to review and send. No send path.",
  author: "Paperclip",
  categories: ["connector", "automation"],
  capabilities: [
    "jobs.schedule",
    "http.outbound",
    "plugin.state.read",
    "plugin.state.write",
    "secrets.read-ref",
  ],
  entrypoints: {
    worker: "./dist/worker.js",
  },
  instanceConfigSchema: {
    type: "object",
    properties: {
      inboxes: {
        type: "array",
        title: "Inboxes",
        description:
          "Shared contact@ inboxes to watch. The Roundcube deep-link host is derived in code as mail.<domain> — do not configure it.",
        items: {
          type: "object",
          properties: {
            address: {
              type: "string",
              title: "Inbox address",
              description: "e.g. contact@bentostudio.io",
            },
            passwordRef: {
              type: "string",
              format: "secret-ref",
              title: "IMAP password",
              description: "Saved Paperclip secret holding this inbox's IMAP app-password.",
            },
            signature: {
              type: "string",
              title: "Signature",
              description: "Appended to every drafted reply for this inbox (the model never writes it).",
            },
          },
          required: ["address", "passwordRef", "signature"],
        },
      },
      discordBotTokenRef: {
        type: "string",
        format: "secret-ref",
        title: "Discord bot token",
        description: "Saved Paperclip secret holding the Discord bot token used to post review embeds.",
      },
      discordChannelId: {
        type: "string",
        title: "Discord channel ID",
        default: DEFAULT_CONFIG.discordChannelId,
      },
      imapHost: {
        type: "string",
        title: "IMAP host",
        default: DEFAULT_CONFIG.imapHost,
      },
      imapPort: {
        type: "number",
        title: "IMAP port",
        default: DEFAULT_CONFIG.imapPort,
      },
      model: {
        type: "string",
        title: "Draft model",
        default: DEFAULT_CONFIG.model,
      },
      batchCapPerRun: {
        type: "number",
        title: "Max emails drafted per run",
        description: "Caps newest-first processing per tick so a backlog drains over successive runs.",
        default: DEFAULT_CONFIG.batchCapPerRun,
      },
    },
    required: ["inboxes", "discordBotTokenRef"],
  },
  jobs: [
    {
      jobKey: JOB_KEY_POLL,
      displayName: "Poll contact@ inboxes",
      description: "Every minute: fetch new mail, draft replies, save to Drafts, post a Discord review embed.",
      schedule: "*/1 * * * *",
    },
  ],
};

export default manifest;
