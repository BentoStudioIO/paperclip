---
name: "model-config-gate"
description: "Use before committing any AI model or agent configuration change — enforces eval-based evidence for model selection, parameters, prompts, tools, and routing"
slug: "model-config-gate"
metadata:
  paperclip:
    slug: "model-config-gate"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/model-config-gate"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/model-config-gate"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/model-config-gate"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/model-config-gate"
---

# Model & AI Config Change Gate

## When This Applies

Any change that modifies:

- Model selection (provider, model ID, version)
- Model parameters (`maxTokens`, `temperature`, `topP`, `topK`, `thinkingBudget`, etc.)
- Agent system prompts or skill prompt content
- Tool descriptions or tool selection logic
- Workflow routing that changes which model/agent handles a task
- Eval judge configuration (model, prompt, scoring rubric)

## 6-Step Protocol

1. **Identify Scope** — Which agent(s)/workflow(s) affected? Which scenarios exercise them? List specific config values changing (old -> new).

2. **Run Baseline Eval** — Run relevant eval scenario(s) with CURRENT config. Save results. Record: score, goalAchieved, duration, key qualitative observations.

3. **Apply Change** — Make the config modification.

4. **Run Comparison Eval** — Run the SAME scenario(s) with new config. Save to new timestamped directory. Record same metrics.

5. **Compare & Document** — Side-by-side: score delta, goal achievement, duration, token usage, output quality. If neutral or negative: REVERT. If positive: document evidence.

6. **Commit with Evidence** — Commit message must include: what changed (old -> new), which eval(s) ran, result (score improvement or "neutral with justification"), reference to result directories.

## Hard Rules

- **No model config changes without eval data.** "It should be better" is not evidence.
- **One variable at a time.** Change model + temperature + maxTokens together and you cannot attribute results. One parameter per commit.
- **No re-attempting reverted changes without new evidence.** If A->B was reverted, trying A->B again requires a documented reason why it would work this time.
- **Eval judge changes need meta-evaluation.** Changing the judge model/prompt/rubric requires re-running a known-good scenario to verify the judge still scores correctly. Changing the measuring stick invalidates previous measurements.
- **Verify provider constraints against docs.** Before setting any parameter, check the provider's API docs for valid ranges, required flags, and rate limits.

## What Counts as an Eval

- Project eval CLI against named scenarios
- Promptfoo, Braintrust, or equivalent with repeatable configs
- One-shot agent tests with measurable output
- Manual comparison with documented observations and actual output samples (acceptable for prompt-only changes without automated scenarios)

## What Does NOT Count

- "I tested it in the UI and it seemed better" — not reproducible
- "The model docs say this parameter improves X" — not your specific use case
- Running eval only AFTER the change (no baseline = no comparison)
- Running a different scenario than the one affected

## Reject on Regression

If evals show regression on any critical dimension, the change does not ship without explicit justification documenting why the regression is acceptable.
