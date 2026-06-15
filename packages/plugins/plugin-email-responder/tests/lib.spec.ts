import { describe, expect, it } from "vitest";
import {
  buildReplyRfc822,
  inboxDomain,
  isMachineNoise,
  roundcubeDeepLink,
  selectUidsToProcess,
  singleReSubject,
  type CursorState,
} from "../src/lib.js";

describe("isMachineNoise", () => {
  it.each([
    ["Auto-Submitted auto-replied", { from: "a@b.com", headers: { "auto-submitted": "auto-replied" } }],
    ["Auto-Submitted auto-generated", { from: "a@b.com", headers: { "auto-submitted": "auto-generated" } }],
    ["List-Unsubscribe present", { from: "a@b.com", headers: { "list-unsubscribe": "<mailto:x@y.com>" } }],
    ["Precedence bulk", { from: "a@b.com", headers: { precedence: "bulk" } }],
    ["Precedence list", { from: "a@b.com", headers: { precedence: "list" } }],
    ["mailer-daemon sender", { from: "MAILER-DAEMON@bentostudio.io", headers: {} }],
    ["postmaster sender", { from: "postmaster@bentostudio.io", headers: {} }],
    ["no-reply sender", { from: "no-reply@stripe.com", headers: {} }],
    ["noreply sender", { from: "noreply@github.com", headers: {} }],
  ])("drops %s", (_label, mail) => {
    expect(isMachineNoise(mail)).toBe(true);
  });

  it.each([
    ["a human sender", { from: "marie@pharmacie.ca", headers: { subject: "Question sur Pharmia" } }],
    ["Auto-Submitted no", { from: "marie@pharmacie.ca", headers: { "auto-submitted": "no" } }],
    ["empty headers", { from: "client@exemple.com", headers: {} }],
  ])("keeps %s for the LLM to judge", (_label, mail) => {
    expect(isMachineNoise(mail)).toBe(false);
  });
});

describe("singleReSubject", () => {
  it.each([
    ["Bonjour", "Re: Bonjour"],
    ["Re: Bonjour", "Re: Bonjour"],
    ["RE: déjà répondu", "RE: déjà répondu"],
    ["re: lowercase", "re: lowercase"],
    ["", "Re: (no subject)"],
  ])("turns %j into %j", (input, expected) => {
    expect(singleReSubject(input)).toBe(expected);
  });
});

describe("buildReplyRfc822", () => {
  const base = {
    fromAddress: "contact@pharmia.ca",
    incomingFrom: "marie@pharmacie.ca",
    incomingSubject: "Question",
    incomingMessageId: "<abc@mail.pharmacie.ca>",
    body: "Bonjour Marie,\n\nMerci pour votre message.\n\nAu plaisir d'échanger,",
    signature: "Mohammed\nCo-fondateur – Pharmia",
  };

  it("appends the signature after the body separated by a blank line", () => {
    const raw = buildReplyRfc822(base);
    expect(raw).toContain("Au plaisir d'échanger,\r\n\r\nMohammed\r\nCo-fondateur – Pharmia\r\n");
  });

  it("de-duplicates the Re: prefix in the Subject header", () => {
    const raw = buildReplyRfc822({ ...base, incomingSubject: "Re: Question" });
    expect(raw).toContain("Subject: Re: Question\r\n");
    expect(raw).not.toContain("Re: Re:");
  });

  it("sets In-Reply-To and References from the incoming Message-ID", () => {
    const raw = buildReplyRfc822(base);
    expect(raw).toContain("In-Reply-To: <abc@mail.pharmacie.ca>\r\n");
    expect(raw).toContain("References: <abc@mail.pharmacie.ca>\r\n");
  });

  it("omits threading headers when no Message-ID is available", () => {
    const raw = buildReplyRfc822({ ...base, incomingMessageId: "" });
    expect(raw).not.toContain("In-Reply-To:");
    expect(raw).not.toContain("References:");
  });

  it("addresses the reply to the incoming sender from the inbox address", () => {
    const raw = buildReplyRfc822(base);
    expect(raw).toContain("From: contact@pharmia.ca\r\n");
    expect(raw).toContain("To: marie@pharmacie.ca\r\n");
  });
});

describe("deep-link interpolation", () => {
  it.each([
    ["contact@pharmia.ca", "pharmia.ca"],
    ["contact@bentostudio.io", "bentostudio.io"],
  ])("derives the mail.<domain> host from %s", (address, domain) => {
    expect(inboxDomain(address)).toBe(domain);
    expect(roundcubeDeepLink(address, 42)).toBe(
      `https://mail.${domain}/?_task=mail&_action=compose&_draft_uid=42&_mbox=Drafts`,
    );
  });

  it("URL-encodes the append UID", () => {
    expect(roundcubeDeepLink("contact@pharmia.ca", "1 2")).toContain("_draft_uid=1%202");
  });
});

describe("selectUidsToProcess", () => {
  it("seeds at the current max UID and processes nothing on first run", () => {
    const result = selectUidsToProcess({
      stored: null,
      mailboxUidValidity: 10,
      availableUids: [3, 7, 5],
      batchCap: 5,
    });
    expect(result.toProcess).toEqual([]);
    expect(result.reset).toBe(false);
    expect(result.seededCursor).toEqual<CursorState>({ uidValidity: 10, lastUid: 7 });
  });

  it("resets and re-seeds when UIDVALIDITY changes", () => {
    const result = selectUidsToProcess({
      stored: { uidValidity: 10, lastUid: 4 },
      mailboxUidValidity: 99,
      availableUids: [1, 2, 3],
      batchCap: 5,
    });
    expect(result.reset).toBe(true);
    expect(result.toProcess).toEqual([]);
    expect(result.seededCursor).toEqual<CursorState>({ uidValidity: 99, lastUid: 3 });
  });

  it("processes only UIDs greater than the stored cursor, oldest first", () => {
    const result = selectUidsToProcess({
      stored: { uidValidity: 10, lastUid: 5 },
      mailboxUidValidity: 10,
      availableUids: [4, 5, 6, 8, 7],
      batchCap: 5,
    });
    expect(result.toProcess).toEqual([6, 7, 8]);
    expect(result.seededCursor).toBeNull();
  });

  it("caps the batch at batchCap newest-of-the-oldest so backlog drains over ticks", () => {
    const result = selectUidsToProcess({
      stored: { uidValidity: 10, lastUid: 0 },
      mailboxUidValidity: 10,
      availableUids: [1, 2, 3, 4, 5, 6, 7],
      batchCap: 3,
    });
    expect(result.toProcess).toEqual([1, 2, 3]);
  });

  it("returns nothing when no UIDs exceed the cursor", () => {
    const result = selectUidsToProcess({
      stored: { uidValidity: 10, lastUid: 9 },
      mailboxUidValidity: 10,
      availableUids: [7, 8, 9],
      batchCap: 5,
    });
    expect(result.toProcess).toEqual([]);
  });
});
