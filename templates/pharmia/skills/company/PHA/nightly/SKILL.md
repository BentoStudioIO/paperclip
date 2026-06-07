---
name: nightly
description: >-
  Unattended exploration skill. User provides a task; the agent discovers axes,
  dispatches the right agents, and consolidates findings into a prioritized
  backlog. Designed for long autonomous runs (tmux, bot, headless).
---
# Nightly Exploration

Autonomous, unattended exploration. The user provides a task description. The agent discovers exploration axes, routes to the right agents, and consolidates findings.

## Input

A task description from the user. Examples:
- "Find all tech debt and ways to reduce code"
- "Map regulatory gaps we haven't addressed yet"
- "Audit all agent prompts and skills for quality"
- "What are users struggling with? Check logs and error patterns"
- "Research competitors and how our product positioning compares"
- "Security sweep + blast radius audit"

The user may optionally specify which agents to use. If not specified, the agent selects automatically.

## Agent Routing

For each axis, pick the best-fit agent from the available agents. The coordinator reads each agent's description and matches it to the axis. When in doubt, dispatch multiple agents — overlap is cheaper than gaps.

## Core Principle: Zero-Context Dispatches

Every agent dispatch and re-dispatch must be self-contained. The dispatched agent receives:
- The full task description
- The specific axis focus
- The output path
- No conversation history, no prior findings, no iteration count

This is the Ralph Loop strategy: context resets prevent rot. Each dispatch is a fresh first-pass. The manifest + findings files are the only continuity — not conversation state.

This matters doubly for nightly runs because context compaction is guaranteed over long sessions. If continuity lived in conversation, it would be lost. With file-driven state, every dispatch after compaction is identical to one before it.

## State Management

Use `TodoWrite` to track your progress across the entire run. This is critical for surviving context compaction over long sessions. Create a todo list at the start of each nightly run with:
- One item per axis (e.g., "Axis: Schema & Validation — round 1")
- Items for verification, re-dispatch rounds, consolidation, and manifest updates

Update todo items as you complete each step. After context compaction, the todo list and manifest together reconstruct your full state.

## Protocol

### 1. Axis Discovery

Read the task. Discover exploration axes — do not use a fixed list. Consider:
- What dimensions does this task touch?
- What agents have relevant expertise?
- What would a thorough human investigator look at?

**Mandatory first step:** Before generating feature or improvement axes, read the project's dependency manifest (`package.json`, `Cargo.toml`, `pyproject.toml`, `go.mod`, or equivalent) and identify the key dependencies. Always include an axis that audits what existing dependencies already support but the project doesn't use. This is typically the highest-ROI axis because it finds capabilities available at zero implementation cost. Extract the top dependencies during this step for injection into every dispatch prompt.

Write the axes to a **manifest file**: `docs/nightly/<date>/manifest.md`

```markdown
# Nightly: <date>
## Task
<user's task description>

## Key Dependencies
<top dependencies extracted from project manifest — injected into every dispatch>

## Axes
- [ ] <axis 1> [agent: <agent-type>] (round 0/5)
- [ ] <axis 2> [agent: <agent-type>] (round 0/5)
- ...

## Status
Started: <timestamp>
```

After writing the manifest, create todo items for all axes and the consolidation step.

### Canonical dispatch prompt

Use this exact prompt for every axis dispatch — initial and re-dispatch alike. **Never vary it.** Do not add axis-specific instructions, elaborations, or focus areas. The agent's own expertise determines what it investigates — the coordinator only provides the axis name and output path.

```
AXIS_DISPATCH_PROMPT:

Explore this axis and write actionable findings.

Task: <user's task description>
Axis: <axis name>
Key dependencies: <top deps from project manifest, e.g. package.json>
Check their APIs (in node_modules/, docs, type definitions) before proposing custom implementations.
Output: write findings to <output file path>

Investigate thoroughly and write a structured findings report to the output path.
```

Violating this template (adding detail, narrowing scope, embedding hints) defeats the Zero-Context principle and biases the agent toward the coordinator's assumptions instead of its own exploration.

### 2. Dispatch

For each axis, dispatch the assigned agent with `AXIS_DISPATCH_PROMPT`. The agent reads whatever it needs (codebase, logs, web, tools) — do not embed content or prior findings in the prompt.

Dispatch independent axes in parallel (max 4 concurrent). Serial for axes that depend on prior findings.

### 3. Verify and Loop

After each agent completes:
1. **Read the findings file on disk** — do not rely on agent result summaries. The agent result notification is a convenience summary that may omit, reframe, or hallucinate findings. The file is the source of truth. If you skip this step, you cannot verify quality or count items accurately.
2. Count the actionable items in the file (grep for headings, numbered items, or severity markers)
3. Update the manifest with the round number and item count: `(round N/5, K findings)`
4. Update the corresponding todo item

**Always re-dispatch** unless one of these conditions is met:
- The axis has reached **5 rounds** (hard cap per axis)
- The total re-dispatch count has reached the **iteration cap**

Re-dispatch uses the identical `AXIS_DISPATCH_PROMPT` — the agent overwrites the previous findings file. Each round is a fresh pass with no knowledge of prior rounds. This is intentional: different agents (or the same agent with different context) will explore different angles, producing progressively more comprehensive findings.

The goal is to maximize exploration depth. A nightly run should take **at least 5 hours**. Do not short-circuit — use every round available.

**Rate limit handling**: If agents hit rate limits, log the cap in the manifest (e.g., `(round 2/5, RATE_LIMITED)`) and consolidate with what you have. Do not treat rate limits as a process failure — they are an external constraint. Note the actual rounds completed vs. the target in the summary stats.

### 4. Consolidate

After all axes have exhausted their rounds or hit the iteration cap, create `docs/nightly/<date>/summary.md`:

```markdown
# Nightly Summary: <date>

## Task
<original task>

## Agents Dispatched
<list with axis assignments and rounds completed>

## High Impact
- <finding + source axis>

## Medium Impact
- <finding + source axis>

## Low Impact / Nice-to-Have
- <finding + source axis>

## Stats
- Axes explored: N
- Total rounds: N (across all axes)
- Findings total: N
```

Rank within each category by ROI: impact / effort. Since each round overwrites the previous file, the consolidation reads the final version of each axis file.

### 5. Update Manifest

```markdown
## Status
Started: <timestamp>
Completed: <timestamp>
Summary: docs/nightly/<date>/summary.md
```

Mark all todo items as completed.

## Compaction Survival

The manifest file and todo list are the sources of truth. If context compacts mid-run:
1. Check your todo list for current progress
2. Re-read the manifest
3. Skip axes that have reached 5 rounds
4. Continue from the next pending axis/round

All findings are on disk — nothing lives only in conversation context.

## Iteration Cap

Default: **100 re-dispatches** total across all axes. Each axis gets up to **5 rounds**. If the iteration cap is reached before all axes complete their rounds, stop dispatching and consolidate.

## Rules

- Never implement fixes. Output is findings only.
- Never commit or push. This is read-only exploration.
- Write all output to `docs/nightly/<date>/`. Clean, self-contained.
- If an agent errors or is unavailable, skip that axis and note it in the manifest. Do not fail the entire run.
- The nightly skill does not define what to look for — the dispatched agents do. This skill only orchestrates.
