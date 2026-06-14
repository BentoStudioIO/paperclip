import { randomUUID } from "node:crypto";
import { eq } from "drizzle-orm";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import {
  agentWakeupRequests,
  agents,
  companies,
  createDb,
  heartbeatRuns,
  issues,
} from "@paperclipai/db";
import {
  redactAdhocContext,
  redactWakePayload,
  selectAdhocCoalesceTarget,
} from "../services/heartbeat.js";
import {
  getEmbeddedPostgresTestSupport,
  startEmbeddedPostgresTestDatabase,
} from "./helpers/embedded-postgres.js";

const mockAdapterExecute = vi.hoisted(() =>
  vi.fn(async () => ({
    exitCode: 0,
    signal: null,
    timedOut: false,
    errorMessage: null,
    summary: "Adhoc redaction integration test run.",
    provider: "test",
    model: "test-model",
  })),
);

vi.mock("../adapters/index.ts", async () => {
  const actual = await vi.importActual<typeof import("../adapters/index.ts")>("../adapters/index.ts");
  return {
    ...actual,
    getServerAdapter: vi.fn(() => ({
      supportsLocalAgentJwt: false,
      execute: mockAdapterExecute,
    })),
  };
});

describe("redactWakePayload", () => {
  it("strips the prompt and free-text body while keeping structural routing keys", () => {
    const redacted = redactWakePayload({
      prompt: "Patient has chest pain, translate to arabic: PHI body",
      message: "more clinical free text",
      text: "even more PHI",
      body: "clinical note",
      issueId: "issue-123",
      taskId: "task-456",
      commentId: "comment-789",
      mutation: "issues.comment.create",
      projectId: "proj-1",
    });

    expect(redacted).not.toHaveProperty("prompt");
    expect(redacted).not.toHaveProperty("message");
    expect(redacted).not.toHaveProperty("text");
    expect(redacted).not.toHaveProperty("body");
    expect(redacted).toMatchObject({
      issueId: "issue-123",
      taskId: "task-456",
      commentId: "comment-789",
      mutation: "issues.comment.create",
      projectId: "proj-1",
      adhoc: true,
    });
  });

  it("returns a non-null adhoc-marked object even when payload is null", () => {
    expect(redactWakePayload(null)).toEqual({ adhoc: true });
  });

  it("does not mutate the input payload (in-memory object stays intact)", () => {
    const original = { prompt: "PHI", issueId: "i-1" };
    const redacted = redactWakePayload(original);
    expect(original).toEqual({ prompt: "PHI", issueId: "i-1" });
    expect(redacted).not.toBe(original);
  });
});

describe("redactAdhocContext", () => {
  it("deletes the clinical-bearing keys and sets the adhoc marker", () => {
    const redacted = redactAdhocContext({
      paperclipWake: { instructions: "translate clinical note" },
      paperclipWakeComment: { body: "PHI comment" },
      paperclipTaskMarkdown: "## Task\nPatient PHI",
      paperclipIssue: { description: "clinical PHI" },
      wakeReason: "Spawned in Discord thread for: Patient has chest pain",
      paperclipContinuationSummary: { body: "prior PHI summary" },
      paperclipEnvironment: "dev",
      paperclipWorkspace: { cwd: "/work" },
      paperclipModelProfile: "thinking",
      source: "automation",
      taskKey: "plugin:discord:session:abc",
      status: "queued",
    });

    expect(redacted).not.toHaveProperty("paperclipWake");
    expect(redacted).not.toHaveProperty("paperclipWakeComment");
    expect(redacted).not.toHaveProperty("paperclipTaskMarkdown");
    expect(redacted).not.toHaveProperty("paperclipIssue");
    expect(redacted).not.toHaveProperty("wakeReason");
    expect(redacted).not.toHaveProperty("paperclipContinuationSummary");

    expect(redacted).toMatchObject({
      paperclipEnvironment: "dev",
      paperclipModelProfile: "thinking",
      source: "automation",
      taskKey: "plugin:discord:session:abc",
      status: "queued",
      adhoc: true,
    });
    expect(redacted.paperclipWorkspace).toEqual({ cwd: "/work" });
  });

  it("does not mutate the input context so the live agent run keeps the full prompt (R3)", () => {
    const liveContext: Record<string, unknown> = {
      paperclipWake: { instructions: "full clinical prompt" },
      paperclipTaskMarkdown: "PHI",
      paperclipEnvironment: "dev",
    };
    const persisted = redactAdhocContext(liveContext);

    expect(liveContext.paperclipWake).toEqual({ instructions: "full clinical prompt" });
    expect(liveContext.paperclipTaskMarkdown).toBe("PHI");
    expect(persisted).not.toBe(liveContext);
    expect(persisted).not.toHaveProperty("paperclipWake");
  });
});

describe("selectAdhocCoalesceTarget", () => {
  it("does not coalesce an adhoc wake into a persisted (non-adhoc) run (R4)", () => {
    const persistedRun = { id: "run-1", contextSnapshot: { taskKey: "k", adhoc: false } };
    expect(selectAdhocCoalesceTarget(persistedRun, true)).toBeNull();
  });

  it("does not coalesce a persisted wake into an adhoc run (R4)", () => {
    const adhocRun = { id: "run-2", contextSnapshot: { taskKey: "k", adhoc: true } };
    expect(selectAdhocCoalesceTarget(adhocRun, false)).toBeNull();
  });

  it("allows coalescing when both wake and target run share the same mode", () => {
    const adhocRun = { id: "run-3", contextSnapshot: { taskKey: "k", adhoc: true } };
    expect(selectAdhocCoalesceTarget(adhocRun, true)).toBe(adhocRun);

    const persistedRun = { id: "run-4", contextSnapshot: { taskKey: "k" } };
    expect(selectAdhocCoalesceTarget(persistedRun, false)).toBe(persistedRun);
  });

  it("passes through a null candidate unchanged", () => {
    expect(selectAdhocCoalesceTarget(null, true)).toBeNull();
    expect(selectAdhocCoalesceTarget(null, false)).toBeNull();
  });
});

const PHI_PROMPT = "Patient has chest pain; translate this clinical note to arabic: <PHI body>";
const CLINICAL_REASON = "Spawned in Discord thread for: Patient has chest pain";

async function seedIdleAgent(db: ReturnType<typeof createDb>) {
  const companyId = randomUUID();
  const agentId = randomUUID();
  await db.insert(companies).values({
    id: companyId,
    name: "Paperclip",
    issuePrefix: `AD${Math.floor(Math.random() * 9000) + 1000}`,
    requireBoardApprovalForNewAgents: false,
  });
  await db.insert(agents).values({
    id: agentId,
    companyId,
    name: "CEO",
    role: "ceo",
    status: "idle",
    adapterType: "process",
    adapterConfig: {},
    runtimeConfig: {},
    permissions: {},
  });
  return { companyId, agentId };
}

const embeddedPostgresSupport = await getEmbeddedPostgresTestSupport();
const describeEmbeddedPostgres = embeddedPostgresSupport.supported ? describe : describe.skip;

if (!embeddedPostgresSupport.supported) {
  console.warn(
    `Skipping embedded Postgres adhoc-redaction tests on this host: ${embeddedPostgresSupport.reason ?? "unsupported environment"}`,
  );
}

describeEmbeddedPostgres("enqueueWakeup adhoc persistence", () => {
  let db!: ReturnType<typeof createDb>;
  let tempDb: Awaited<ReturnType<typeof startEmbeddedPostgresTestDatabase>> | null = null;
  let heartbeatService!: typeof import("../services/heartbeat.ts").heartbeatService;

  beforeAll(async () => {
    const started = await startEmbeddedPostgresTestDatabase("paperclip-heartbeat-adhoc-");
    db = createDb(started.connectionString);
    tempDb = started;
    ({ heartbeatService } = await import("../services/heartbeat.ts"));
  }, 120_000);

  afterAll(async () => {
    await db?.$client?.end?.({ timeout: 0 });
    await tempDb?.cleanup();
  });

  it("redacts the prompt+reason from the wake-request row and marks it adhoc", async () => {
    const heartbeat = heartbeatService(db);
    const { agentId } = await seedIdleAgent(db);

    const run = await heartbeat.wakeup(agentId, {
      source: "automation",
      triggerDetail: "system",
      reason: CLINICAL_REASON,
      payload: { prompt: PHI_PROMPT },
      requestedByActorType: "system",
      requestedByActorId: "plugin:test",
      adhoc: true,
    });

    expect(run).not.toBeNull();
    const request = await db
      .select()
      .from(agentWakeupRequests)
      .where(eq(agentWakeupRequests.runId, run!.id))
      .then((rows) => rows[0]);

    expect(request).toBeDefined();
    expect(request!.runId).toBe(run!.id);
    expect(request!.source).toBe("automation");
    expect(request!.reason).toBeNull();

    const payload = (request!.payload ?? {}) as Record<string, unknown>;
    expect(payload).not.toHaveProperty("prompt");
    expect(JSON.stringify(payload)).not.toContain("chest pain");
    expect(payload.adhoc).toBe(true);
  });

  it("redacts the clinical keys from the run context_snapshot but keeps operational keys", async () => {
    const heartbeat = heartbeatService(db);
    const { agentId } = await seedIdleAgent(db);

    const run = await heartbeat.wakeup(agentId, {
      source: "automation",
      triggerDetail: "system",
      reason: CLINICAL_REASON,
      payload: { prompt: PHI_PROMPT },
      contextSnapshot: {
        taskKey: "plugin:test:session:abc",
        paperclipEnvironment: "dev",
      },
      requestedByActorType: "system",
      requestedByActorId: "plugin:test",
      adhoc: true,
    });

    const persisted = await db
      .select({ contextSnapshot: heartbeatRuns.contextSnapshot })
      .from(heartbeatRuns)
      .where(eq(heartbeatRuns.id, run!.id))
      .then((rows) => rows[0]);

    const ctx = (persisted!.contextSnapshot ?? {}) as Record<string, unknown>;
    expect(ctx.adhoc).toBe(true);
    expect(ctx).not.toHaveProperty("paperclipWake");
    expect(ctx).not.toHaveProperty("paperclipTaskMarkdown");
    expect(ctx).not.toHaveProperty("paperclipWakeComment");
    expect(ctx).not.toHaveProperty("paperclipIssue");
    expect(ctx).not.toHaveProperty("wakeReason");
    expect(ctx).not.toHaveProperty("paperclipContinuationSummary");
    expect(JSON.stringify(ctx)).not.toContain("chest pain");
    expect(ctx.taskKey).toBe("plugin:test:session:abc");
    expect(ctx.paperclipEnvironment).toBe("dev");
  });

  it("regression: without adhoc the prompt, reason and wakeReason are persisted unchanged", async () => {
    const heartbeat = heartbeatService(db);
    const { agentId } = await seedIdleAgent(db);

    const run = await heartbeat.wakeup(agentId, {
      source: "automation",
      triggerDetail: "system",
      reason: CLINICAL_REASON,
      payload: { prompt: PHI_PROMPT },
      requestedByActorType: "system",
      requestedByActorId: "plugin:test",
    });

    const request = await db
      .select()
      .from(agentWakeupRequests)
      .where(eq(agentWakeupRequests.runId, run!.id))
      .then((rows) => rows[0]);
    const payload = (request!.payload ?? {}) as Record<string, unknown>;
    expect(payload.prompt).toBe(PHI_PROMPT);
    expect(request!.reason).toBe(CLINICAL_REASON);

    const persisted = await db
      .select({ contextSnapshot: heartbeatRuns.contextSnapshot })
      .from(heartbeatRuns)
      .where(eq(heartbeatRuns.id, run!.id))
      .then((rows) => rows[0]);
    const ctx = (persisted!.contextSnapshot ?? {}) as Record<string, unknown>;
    expect(ctx.wakeReason).toBe(CLINICAL_REASON);
    expect(ctx.adhoc).toBeUndefined();
  });

  it("redacts the prompt from an adhoc SKIP-path row (wakeOnDemand disabled)", async () => {
    const heartbeat = heartbeatService(db);
    const companyId = randomUUID();
    const agentId = randomUUID();
    await db.insert(companies).values({
      id: companyId,
      name: "Paperclip",
      issuePrefix: `SK${Math.floor(Math.random() * 9000) + 1000}`,
      requireBoardApprovalForNewAgents: false,
    });
    // wakeOnDemand:false → an automation wake is skipped (returns null) and
    // writeSkippedRequest persists the row. Under adhoc it must carry no prompt.
    await db.insert(agents).values({
      id: agentId,
      companyId,
      name: "CEO",
      role: "ceo",
      status: "idle",
      adapterType: "process",
      adapterConfig: {},
      runtimeConfig: { heartbeat: { wakeOnDemand: false } },
      permissions: {},
    });

    const run = await heartbeat.wakeup(agentId, {
      source: "automation",
      triggerDetail: "system",
      reason: CLINICAL_REASON,
      payload: { prompt: PHI_PROMPT },
      requestedByActorType: "system",
      requestedByActorId: "plugin:test",
      adhoc: true,
    });
    expect(run).toBeNull();

    const skipped = await db
      .select()
      .from(agentWakeupRequests)
      .where(eq(agentWakeupRequests.agentId, agentId))
      .then((rows) => rows[0]);
    expect(skipped).toBeDefined();
    expect(skipped!.status).toBe("skipped");
    expect(skipped!.reason).toBe("heartbeat.wakeOnDemand.disabled");
    const payload = (skipped!.payload ?? {}) as Record<string, unknown>;
    expect(payload).not.toHaveProperty("prompt");
    expect(JSON.stringify(payload)).not.toContain("chest pain");
    expect(payload.adhoc).toBe(true);
  });

  it("does not cross-mode coalesce an adhoc wake into a persisted running issue run (R4)", async () => {
    const heartbeat = heartbeatService(db);
    const companyId = randomUUID();
    const agentId = randomUUID();
    const issueId = randomUUID();
    const runId = randomUUID();
    const issuePrefix = `CM${Math.floor(Math.random() * 9000) + 1000}`;
    await db.insert(companies).values({
      id: companyId,
      name: "Paperclip",
      issuePrefix,
      requireBoardApprovalForNewAgents: false,
    });
    await db.insert(agents).values({
      id: agentId,
      companyId,
      name: "CEO",
      role: "ceo",
      status: "running",
      adapterType: "process",
      adapterConfig: {},
      runtimeConfig: {},
      permissions: {},
    });
    // A persisted (non-adhoc) execution run already locks the issue.
    await db.insert(heartbeatRuns).values({
      id: runId,
      companyId,
      agentId,
      invocationSource: "assignment",
      triggerDetail: "system",
      status: "running",
      contextSnapshot: {
        issueId,
        taskId: issueId,
        wakeReason: "issue_assigned",
        paperclipTaskMarkdown: "persisted clinical body",
      },
    });
    await db.insert(issues).values({
      id: issueId,
      companyId,
      title: "Locked issue",
      status: "in_progress",
      priority: "medium",
      assigneeAgentId: agentId,
      executionRunId: runId,
      executionAgentNameKey: "ceo",
      executionLockedAt: new Date(),
      issueNumber: 1,
      identifier: `${issuePrefix}-1`,
    });

    // An adhoc wake for the SAME issue+agent must NOT merge into the persisted run.
    const result = await heartbeat.wakeup(agentId, {
      source: "automation",
      triggerDetail: "system",
      reason: CLINICAL_REASON,
      payload: { prompt: PHI_PROMPT, issueId },
      contextSnapshot: { issueId, taskId: issueId },
      requestedByActorType: "system",
      requestedByActorId: "plugin:test",
      adhoc: true,
    });
    // Cross-mode coalesce is refused → the wake is deferred behind the lock, not merged.
    expect(result).toBeNull();

    // The persisted running run is untouched: no clinical body re-merged, no marker flip.
    const lockedRun = await db
      .select({ contextSnapshot: heartbeatRuns.contextSnapshot })
      .from(heartbeatRuns)
      .where(eq(heartbeatRuns.id, runId))
      .then((rows) => rows[0]);
    const lockedCtx = (lockedRun!.contextSnapshot ?? {}) as Record<string, unknown>;
    expect(lockedCtx.adhoc).toBeUndefined();
    expect(lockedCtx.paperclipTaskMarkdown).toBe("persisted clinical body");

    // The deferred adhoc row stores a redacted context (no prompt, marked adhoc).
    const deferred = await db
      .select()
      .from(agentWakeupRequests)
      .where(eq(agentWakeupRequests.status, "deferred_issue_execution"))
      .then((rows) => rows[0]);
    expect(deferred).toBeDefined();
    const deferredPayload = (deferred!.payload ?? {}) as Record<string, unknown>;
    expect(deferredPayload).not.toHaveProperty("prompt");
    expect(JSON.stringify(deferredPayload)).not.toContain("chest pain");
    expect(deferredPayload.adhoc).toBe(true);
  });
});
