---
name: "pharmia-agents"
description: "Pharmia agent architecture, model defaults, eval system, and key file paths"
slug: "pharmia-agents"
metadata:
  paperclip:
    slug: "pharmia-agents"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-agents"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-agents"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-agents"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-agents"
user-invocable: false
---

# Pharmia Agent Architecture

## Mastra Agents

> Model config changes often. VERIFY against `agentModels.ts` (`MODEL_DEFAULTS` + `MODEL_RINGS`) before trusting this table — it is a convenience snapshot, not the source of truth.

| Role                       | Agent                            | Model                                                    | Provider  | Thinking    |
| -------------------------- | -------------------------------- | -------------------------------------------------------- | --------- | ----------- |
| Coordinator                | pharmiaCoordinatorAgent          | claude-opus-4-6                                          | anthropic | 5000 tokens |
| Quebec Docs (subagent)     | pharmiaQuebecDocsAgent           | kimi-k2p6                                                | fireworks | high        |
| Health Products (subagent) | pharmiaCanadaHealthProductsAgent | kimi-k2p6                                                | fireworks | high        |
| Chat Form                  | pharmiaChatFormAgent             | claude-sonnet-4-6                                        | anthropic | low         |
| Phone                      | pharmiaPhoneAgent                | claude-sonnet-4-6                                        | anthropic | none        |
| Atlas                      | pharmiaAtlasAgent                | **ring** — see below                                     | —         | none        |
| Copilot                    | (no own agent; derives from `atlasConfig`, CopilotKit, `memory: undefined`) | = Atlas ring             | —         | none        |
| Note Generator             | pharmiaNoteGeneratorAgent        | gemini-3.1-flash-lite                                    | google    | -           |
| Utility                    | pharmiaUtilityAgent              | gemini-3.1-flash-lite                                    | google    | -           |

### Atlas model ring (`MODEL_RINGS.atlas` — unified across ALL envs since 2026-06-03)

- Tier 0 (primary): **gemini-3.5-flash** / google
- Tier 1 (failover): **kimi-k2p6** (`accounts/fireworks/models/kimi-k2p6`) / fireworks
- Per-request rescue (`rescueModel = MODEL_DEFAULTS.atlasFallback`): gemini-3.5-flash / google (never rotates)
- DeepSeek V4-Pro removed from the ring (too slow). No env branch — every env runs the same two tiers.
- Invariant: both tiers MUST share `thinking: 'none'` (getOrCreateRing Invariant 3). Gemini `'none'` → Google `thinkingLevel: 'minimal'`; the live `atlasThinkingRouter` overrides Gemini per-request (révision-pharmaco / consultation-voyage → `low`, rest → `minimal`), gated on `provider === 'google'`.
- Edit the ring at `agentModels.ts:MODEL_RINGS.atlas`; validate with the `model-config-gate` skill + `threads modelmix`.

Echo / observational-memory run on their own `MODEL_DEFAULTS` keys: `echoAnalyzer` = gemini-3.5-flash/google, `echoAnswerExtractor` = gpt-oss-120b/cerebras, `observationalMemory` = deepseek-v4-flash/fireworks-oai.

## Agent Factory Pattern

- `factory.ts` — `createPharmiaAgent(config)` builds agents with shared options
- `agentModels.ts` — `MODEL_DEFAULTS` single source of truth for all model configs
- `agentOptions.ts` — shared agent options (memory, tools, Langfuse tracing)
- Prompts in code: `packages/api/src/mastra/prompts/` (.md files)
- Skills from Outline: "Agent Skills" collection loaded via `OutlineFilesystem`
- Technical behavior = in-code .md prompts; Interaction/clinical behavior = Outline skills

## Key File Paths

- Agent configs: `packages/api/src/mastra/agents/`
- Patient agents: `packages/api/src/mastra/agents/patient/`
- Shared patient config: `packages/api/src/mastra/agents/patient/patientConversationConfig.ts`
- Tools: `packages/api/src/mastra/tools/`
- Workflows: `packages/api/src/mastra/workflows/`
- Coordinator workflow: `packages/api/src/mastra/workflows/consultation-analysis/`
- Eval config: `packages/api/src/evals/config.ts`
- Eval coordinator: `packages/api/src/evals/coordinator/`
- Eval chat: `packages/api/src/evals/chat/`
- CLI entry: `packages/api/src/cli/index.ts`

## Eval System

Three eval types, all loading scenarios from Outline "AI Experiments" collection.

**Coordinator eval** (`pharmia eval analysis`): Full 3-agent network. Default: 50 steps, 360s, 5000 thinking tokens.
**Chat eval** (`pharmia eval chat run`): Multi-turn with patient simulator + optional judge. Default: 30 turns, 180s.
**Agent eval** (`pharmia eval agent run`): One-shot test. Opus models blocked. Default: 10 steps, 120s.

Results saved to `packages/api/src/evals/results/{timestamp}/` with eval.json, scenario.md, result.json, response.md, steps.json, prompts/.

## Consultation Flow

Two paths (chat/phone) converge at coordinator workflow:

1. Chat: create → start → patient chats with chatFormAgent → sendForAnalysis → coordinator workflow → recommendations
2. Phone: initiate → LiveKit dials → phoneAgent voice session → on success → coordinator workflow → recommendations

Coordinator workflow steps: generateAiNotes → coordinatorStep (3-agent network) → saveConsultationResult

Status transitions are atomic CAS. Events via in-process EventEmitter.
