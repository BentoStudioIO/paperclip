---
name: "pharmia-cli"
description: "Pharmia CLI commands: evals, agent testing, tool invocation, workflows, and Outline operations"
slug: "pharmia-cli"
metadata:
  paperclip:
    slug: "pharmia-cli"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-cli"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-cli"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-cli"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/pharmia-cli"
user-invocable: true
---

# Pharmia CLI

The CLI lives at `packages/api/` and is invoked via `npm run pharmia -- <command>`. Always run from repo root.

## Commands

### `pharmia eval` — Run AI agent evaluations

```bash
# List coordinator analysis scenarios (from Outline)
npm run pharmia -- eval analysis list

# Run coordinator eval on a scenario
npm run pharmia -- eval analysis --scenario "<name-or-id>" [--verbose] [--provider anthropic] [--model claude-sonnet-4-6]

# List chat scenarios
npm run pharmia -- eval chat list

# Run chat eval (multi-turn with patient simulator)
npm run pharmia -- eval chat run "<scenario>" [--judge] [--max-turns 30]

# Run one-shot agent test
npm run pharmia -- eval agent run <agent-name> --prompt "your prompt here" [--provider openrouter] [--model ...]

# Available agents: chat-form, phone, canada-health-products, clinical-analyzer, copilot, atlas, note-generator, quebec-docs

# Dump agent's resolved system prompt
npm run pharmia -- eval agent prompt <agent-name>
```

### `pharmia tools` — Run Mastra tools directly

```bash
npm run pharmia -- tools drugs "acetaminophen"
npm run pharmia -- tools nhp "vitamin D"
npm run pharmia -- tools inspq "malaria"
npm run pharmia -- tools piq "influenza vaccine"
npm run pharmia -- tools pubmed "metformin diabetes"
npm run pharmia -- tools pubmed-article "<pmid>"
```

### `pharmia call` — Initiate phone consultation

```bash
npm run pharmia -- call 4389225580
```

### `pharmia outline` — Outline document operations

```bash
npm run pharmia -- outline collections
npm run pharmia -- outline list <collection-id>
npm run pharmia -- outline doc <document-id>
npm run pharmia -- outline search "query"
```

### `pharmia workflow` — Workflow operations

```bash
npm run pharmia -- workflow list
npm run pharmia -- workflow run <workflow-name> --consultation-id <id>
```

### `pharmia autumn` — Billing config

```bash
npm run pharmia -- autumn push --url <autumn-url>
```

## Important Notes

- **Opus models are blocked** in agent evals (too expensive). Use sonnet/flash/kimi.
- **Eval results** saved to `packages/api/src/evals/results/{timestamp}/`
- **Scenarios come from Outline** "AI Experiments" collection — use `list` to discover available ones
- **Process lock**: only one eval can run at a time (file lock with 20-min timeout)
- **For verbose output**: add `--verbose` flag to see step-by-step agent activity
