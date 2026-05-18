---
name: "clarification-gate"
description: "Use before planning or implementing any task — surfaces ambiguities, classifies them, and blocks work on unresolved blockers"
slug: "clarification-gate"
metadata:
  author: "vortex"
  paperclip:
    slug: "clarification-gate"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/clarification-gate"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/clarification-gate"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/clarification-gate"
  type: "custom"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/clarification-gate"
---

# Clarification Gate

## When This Runs

After receiving a task request, before writing any plan or code. This is a mandatory pre-planning step.

## Protocol

### Step 1: Discovery Read (Optional, One Pass)

Scan repo structure, relevant config files, existing code. Goal: self-resolve ambiguities the codebase already answers. Do NOT use this as an excuse to skip asking — only resolve what is clearly documented.

### Step 2: Identify Ambiguities

Check the request for:

- **Scope gaps** — What's included vs excluded?
- **Behavioral unknowns** — What happens in edge cases? Error states? Empty data?
- **Integration points** — Which existing systems does this touch? Hidden constraints?
- **Priority conflicts** — Does this conflict with or depend on other in-flight work?
- **Naming/terminology** — Does a term map to multiple things in the codebase?
- **Acceptance criteria** — How will we know this is done?

### Step 3: Classify Each Ambiguity

- **SELF-RESOLVED** — Answered from codebase or research. State the answer inline. Do not ask the user.
- **DEFAULTABLE** — Safe assumption exists. State the default and why. Propose: "I'll assume X unless you say otherwise."
- **BLOCKING** — Cannot proceed without an answer. No safe default exists.

### Step 4: Ask (If Needed)

- Group questions by theme
- For each question, explain WHY it matters (not just what)
- For DEFAULTABLE items, propose the default
- Maximum 7 questions per round — if more exist, the request may need decomposition

### Step 5: Proceed

Only after all BLOCKING questions are answered and all DEFAULTABLE items confirmed or overridden.

## Hard Rules

- **Never plan with unresolved BLOCKERs.** A plan built on assumptions about blocking items will be wrong.
- **Never ask questions answerable from a 30-second codebase read.** Do the read first.
- **Max 7 questions per round.** More than that means the request is too large or too vague.
- **If zero BLOCKERs, skip straight to planning.** Don't ask for the sake of asking.

## Scope Control

- Plan only what was requested
- Flag nice-to-haves separately in an "Out of Scope" section
- If you discover the request implies more work than stated, surface that as a DEFAULTABLE item ("This also requires X — should I include it?")
