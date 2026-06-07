---
name: "echo-pipeline-rca"
description: "Standardized root-cause-analysis trace path for ONE bad Echo / live-consult session — recording → STT → analyzer (debounce/dedupe/serialize) → broadcast → note. Use when handed an Echo session / consultation id or a report of a bad note, missing insight, garbled transcript, or stuck rail. Owns only the SEQUENCE — STT/TTS facts live in memory stt-tts-providers, LiveKit incidents in memory livekit."
slug: "echo-pipeline-rca"
metadata:
  paperclip:
    slug: "echo-pipeline-rca"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/echo-pipeline-rca"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/echo-pipeline-rca"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/echo-pipeline-rca"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/echo-pipeline-rca"
---

# Echo / Consult Pipeline RCA — "Why Was This Session Bad"

This is the Echo/consult equivalent of what `threads` + `atlas-rca` give Atlas:
the load-bearing trace path for ONE session. Run it when handed an Echo session
id, a consultation id, or a report of: a bad/empty/wrong clinical note, a missing
or duplicate insight, a garbled/empty transcript, a stuck or churning insights
rail, or a recording that never finalized. This skill owns ONLY the sequence —
provider facts and infra incidents are single-sourced (DRY note at the bottom).

## The Two Pipelines (don't confuse them)
- **Echo (audio-note)** — pharmacist records audio → MinIO → batch STT → note.
  Route namespace `/api/echo/*`, tables `echo_session` / `echo_recording` /
  `echo_note`. NO live insight rail.
- **Live consultation (patient↔AI)** — turn transcript → streaming analyzer →
  insights rail (SSE). Surfaced through the SAME echo router namespace
  (`insightsRouter`) but is a different flow. Insights persist to
  `consultationInsight`.
Identify which one the complaint is about FIRST — the file map and tables differ.

## Layer 0 — Known-Cause Check (before tracing)
Grep the memos; most pathologies are banked:
```sh
grep -rl '<symptom keyword>' ~/.claude/projects/-home-vortex-Documents-PharmaMate/memory/
```
- `stt-tts-providers.md` — provider defaults, `domain:'medical'`, fr vs fr-CA,
  `maxDelay` (Speechmatics default 4s — too high for live voice). Symptom: bad/
  late transcription, wrong language.
- `livekit.md` — INC-1/INC-2 (psrpc deadlock, "no response from servers",
  permanent "Not Ready"). Symptom: phone-call recording never started / dropped.
- `mastra-image-handling.md` — only if the note path ingested an attachment.

## Layer 1 — Service File Map (the load-bearing path)
Walk it in order; each box is where that stage can fail.
- **Capture / upload** — `routes/echo/recordingRouter.ts`,
  `routes/echo/audioStreamHandler.ts` (MinIO proxy GET
  `/api/echo/audio/:recordingId`), `routes/echo/mergedAudioHandler.ts`. Audio in
  MinIO; row in `echo_recording`.
- **STT (batch, Echo)** — `services/echo/transcriptionService.ts` → `clients/stt`
  (`transcribeBatch`, Speechmatics enhanced `domain:'medical'`, fallback Deepgram).
  `utils/audioFormat.ts` (`detectAudioFormat` / `repairWebM`) runs first — a
  corrupt/unrepaired WebM is a classic empty-transcript cause.
- **Analyzer (live consult only)** — `services/echo/analyzer/`:
  `debouncer.ts` (throttle-batcher: timer armed by FIRST sentence after a flush,
  NOT reset; `flushAt` hard cap; **per-consultation serialization** so only one
  `onFlush` runs at a time — overlap is impossible by construction; optional
  `cooldownMs` for a steady visible cadence) → `pipeline.ts`
  (`buildAnalyzerPipeline`, `RECENT_WINDOW=15`) → `runAnalyzer.ts` (LLM call on
  the analyzer agent's failover ring) → `dedupe.ts` (`computeDedupeHash` =
  sha1 of normalized `text:type`, stored in `consultationInsight.dedupeHash`,
  queried via `idx_insight_consult_dedupe`) → persist.
- **Broadcast** — `services/echo/analyzer/insightBroadcast.ts` (in-process
  `EventEmitter`, topic `c:<consultationId>`, events `created|updated|heartbeat`)
  → `routes/echo/insightsRouter.ts` `stream` (SSE; replays active insights on
  connect so a fresh subscriber misses nothing). Wiring:
  `routes/echo/insightsRouter.pipeline.ts`.
- **Note** — `services/echo/loadNoteTemplate.ts` + `templateLoader.ts` +
  `noteStyleInstructions.ts` (SOAP / Q1-Q2-Q3 / DAP) → analyzer/answer-extractor
  agents (`mastra/agents/pharmiaEchoAnalyzerAgent.ts`,
  `pharmiaEchoAnswerExtractorAgent.ts`, prompts in `mastra/prompts/echo_*.md`) →
  `echo_note` row.

## Layer 2 — Logs (Loki, scope ALWAYS to the API)
Always `{service_name="pharmia-api"}` — LiveKit SIP also emits `client_error`,
and Loki echoes your search string in querier logs.
```sh
loki <env> search "<consultationId or recordingId>" --since 24h
loki <env> errors --service pharmia-api --since 6h
loki <env> search "phone: [TRACE]" --since 6h     # phone-call finalize/flush
```
The phone path logs `phone: [TRACE] Langfuse flush failed` when a call trace is
lost — that means cost/observability for that call is gone, not that the call
failed. STT emits `[STT]`-tagged lines.

## Layer 3 — Langfuse (the per-session trace)
Both pipelines nest Mastra observations under a single trace.
- **Phone:** `buildPhoneTracingOptions` (`services/phone/phoneTrace.ts`) sets
  `tags:['phone',…]`, `sessionId = consultationId`. Pull it:
  ```sh
  langfuse api traces list --tags phone --limit 20 --fields core,metrics --json
  ```
  then jq-filter on `metadata.consultationId` (no server-side text search).
- **Echo batch STT** traces via `transcriptionService.ts` (`uuidToHex` →
  trace id, `traced()` util). Use `--tags` for the surface, then jq on input/
  output to see what the analyzer/extractor actually received.

## Layer 4 — DB (ground truth)
```sh
pg <env> mastra   # (Atlas/consult messages live here; see threads CLI)
pg <env>          # clinical DB for the echo_* / consultationInsight tables
```
- `echo_session` (status), `echo_recording` (audio key, transcript words),
  `echo_note` (generated note) — Echo path.
- `consultationInsight` (`dedupeHash`, `status` created→dismissed) — live rail.
  A missing insight that the LLM *did* emit but isn't on the rail = persisted but
  dedupe-collided, OR broadcast subscriber attached after emit (Layer 1 replay
  should cover the latter — if it doesn't, that's the bug).

## Layer 5 — VERDICT (mandatory)
```
VERDICT
- Pipeline:   <echo-note | live-consult>
- Stage:      <capture | stt | analyzer | dedupe | broadcast | note>
- Root cause: <one concrete sentence>
- Evidence:   <session/consult id + the log line / trace / DB row>
- Fix owner:  <service file from Layer 1, or memory stt-tts-providers / livekit>
- Known/new:  <cite memo, OR "new — bank a memo under …/memory/">
```

## DRY — This Skill Owns ONLY The Sequence
- STT/TTS providers, defaults, pricing, fr-CA voice facts → memory
  `stt-tts-providers.md`.
- LiveKit deploy / psrpc incidents → memory `livekit.md`.
- Agent model defaults / ring → **`pharmia-agents`**; any config change →
  **`model-config-gate`**.
- Atlas thread RCA (different surface) → **`atlas-rca`** + `threads` CLI.
Do not restate any of that here.
