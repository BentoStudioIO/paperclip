---
name: "claude-prompting"
description: "Official Claude prompt engineering best practices from Anthropic (Claude 4.6 era). Use when writing, reviewing, or enhancing prompts for Claude models — system prompts, agent instructions, tool descriptions, or any LLM prompt targeting Claude."
slug: "claude-prompting"
metadata:
  paperclip:
    slug: "claude-prompting"
    skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/claude-prompting"
  paperclipSkillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/claude-prompting"
  skillKey: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/claude-prompting"
key: "company/57cd0843-fe5a-42d5-a6f6-c4e896fee84e/claude-prompting"
---


# Claude Prompt Engineering Best Practices

Source: Anthropic official documentation (platform.claude.com), covering Claude Opus 4.6, Sonnet 4.6, and Haiku 4.5.

## When to Use

- Writing or enhancing system prompts for Claude-powered agents
- Reviewing prompt quality against Anthropic's latest guidance
- Designing tool descriptions or structured output schemas
- Migrating prompts from older Claude models to 4.6
- Building agentic systems with Claude

---

## General Principles

### Be clear and direct

Claude responds well to clear, explicit instructions. Be specific about desired output format and constraints. If you want thorough behavior, explicitly request it.

**Golden rule:** Show your prompt to a colleague with minimal context. If they'd be confused, Claude will be too.

- Provide instructions as sequential steps using numbered lists or bullet points when order matters.
- Instead of "Create a dashboard", say "Create an analytics dashboard. Include as many relevant features and interactions as possible. Go beyond the basics."

### Add context — explain WHY

Providing motivation behind instructions helps Claude generalize better.

- Instead of: `NEVER use ellipses`
- Better: `Your response will be read aloud by a text-to-speech engine, so never use ellipses since the TTS engine won't know how to pronounce them.`

### Use examples effectively (few-shot / multishot)

Examples are the most reliable way to steer output format, tone, and structure.

- Use 3-5 examples for best results.
- Make them relevant, diverse (cover edge cases), and structured.
- Wrap in `<example>` tags (multiple in `<examples>`) so Claude distinguishes them from instructions.

```xml
<examples>
<example>
<input>The conference is March 15, 2025 in San Francisco.</input>
<output>{"date": "2025-03-15", "event": "conference", "location": "San Francisco"}</output>
</example>
</examples>
```

### Structure prompts with XML tags

XML tags help Claude parse complex prompts unambiguously. Wrap each content type in its own tag.

- Use consistent, descriptive tag names: `<instructions>`, `<context>`, `<input>`, `<constraints>`.
- Nest tags when content has natural hierarchy.

### Give Claude a role

A single sentence in the system prompt focusing Claude's behavior makes a difference:

```python
message = client.messages.create(
    model="claude-opus-4-6",
    system="You are a helpful coding assistant specializing in Python.",
    messages=[{"role": "user", "content": "How do I sort a list of dicts?"}],
)
```

### Long context prompting (20k+ tokens)

- **Put longform data at the top** of your prompt, above queries and instructions. Queries at the end improve quality by up to 30%.
- **Structure documents with XML tags:**

```xml
<documents>
  <document index="1">
    <source>annual_report_2023.pdf</source>
    <document_content>{{ANNUAL_REPORT}}</document_content>
  </document>
</documents>

Analyze the report and identify strategic advantages.
```

- **Ground responses in quotes:** Ask Claude to quote relevant parts before answering. This cuts through noise in long documents.

### Model self-knowledge

```
The assistant is Claude, created by Anthropic. The current model is Claude Opus 4.6.
When an LLM is needed, default to Claude Opus 4.6 (model string: claude-opus-4-6).
```

---

## Output and Formatting

### Communication style

Claude 4.6 is more concise and direct than previous models:

- More grounded progress reports (no self-congratulation)
- More conversational and less machine-like
- May skip verbal summaries after tool calls

If you want summaries: `After completing a task involving tool use, provide a quick summary of the work you've done.`

### Control output format

1. **Say what TO DO, not what NOT to do.**
   - Instead of: "Do not use markdown"
   - Try: "Write in smoothly flowing prose paragraphs."

2. **Use XML format indicators:**
   `Write prose sections in <smoothly_flowing_prose_paragraphs> tags.`

3. **Match your prompt style to desired output style.** Removing markdown from your prompt reduces markdown in output.

4. **Explicit formatting guidance to minimize markdown:**

```xml
<avoid_excessive_markdown_and_bullet_points>
Write in clear, flowing prose using complete paragraphs. Reserve markdown for
inline code, code blocks, and simple headings. Avoid bold, italics, and bullet
lists unless presenting truly discrete items or the user explicitly requests it.
Instead of listing items with bullets, incorporate them naturally into sentences.
</avoid_excessive_markdown_and_bullet_points>
```

### Prefilling is deprecated

Starting with Claude 4.6, prefilled responses on the last assistant turn are **no longer supported**. Migration paths:

| Old pattern                              | New approach                                                                                  |
| ---------------------------------------- | --------------------------------------------------------------------------------------------- |
| Force output format (JSON, etc.)         | Use Structured Outputs or just ask — Claude 4.6 follows format instructions reliably          |
| Skip preamble (`Here is the summary:\n`) | System prompt: "Respond directly without preamble." Or use XML tags / structured outputs      |
| Avoid refusals                           | Claude 4.6 handles appropriate refusals much better — clear prompting is sufficient           |
| Continue partial completions             | User message: "Your previous response ended with `[text]`. Continue from where you left off." |

---

## Tool Use

### Be explicit about action vs suggestion

Claude 4.6 distinguishes between suggesting and acting. Be explicit:

- "Can you suggest changes?" → Claude suggests only
- "Change this function to improve performance." → Claude acts
- "Make these edits to the auth flow." → Claude acts

To make Claude proactive by default:

```xml
<default_to_action>
By default, implement changes rather than only suggesting them. If intent is
unclear, infer the most useful action and proceed, using tools to discover
missing details instead of guessing.
</default_to_action>
```

### Dial back aggressive tool-triggering language

Claude 4.6 is more responsive to system prompts than previous models. Prompts designed to reduce undertriggering may now **overtrigger**.

- Instead of: `CRITICAL: You MUST use this tool when...`
- Use: `Use this tool when...`

### Parallel tool calling

Claude 4.6 excels at parallel tool execution. Boost to ~100% success:

```xml
<use_parallel_tool_calls>
If you intend to call multiple tools and there are no dependencies between them,
make all independent calls in parallel. Never use placeholders or guess missing
parameters. If some calls depend on previous results, call those sequentially.
</use_parallel_tool_calls>
```

---

## Thinking and Reasoning

### Adaptive thinking (Claude 4.6)

Claude 4.6 uses adaptive thinking (`thinking: {type: "adaptive"}`) where it dynamically decides when and how much to think. Control depth via the `effort` parameter.

```python
client.messages.create(
    model="claude-opus-4-6",
    max_tokens=64000,
    thinking={"type": "adaptive"},
    output_config={"effort": "high"},  # or max, medium, low
    messages=[{"role": "user", "content": "..."}],
)
```

**`budget_tokens` is deprecated.** Prefer `effort` parameter or `max_tokens` as a hard limit.

### Reduce overthinking

Claude Opus 4.6 does significantly more upfront exploration than previous models. To constrain:

- Replace blanket defaults ("Default to using [tool]") with targeted instructions ("Use [tool] when it would enhance understanding")
- Remove over-prompting — tools that undertriggered before now trigger appropriately
- Use lower `effort` settings as fallback

```
When deciding how to approach a problem, choose an approach and commit to it.
Avoid revisiting decisions unless you encounter contradicting information.
```

### Guide thinking behavior

```
After receiving tool results, carefully reflect on quality and determine optimal
next steps before proceeding. Use thinking to plan and iterate, then take action.
```

To reduce unnecessary thinking:

```
Extended thinking adds latency and should only be used when it will meaningfully
improve answer quality — typically for multi-step reasoning problems. When in
doubt, respond directly.
```

### Manual Chain-of-Thought (when thinking is off)

- Use `<thinking>` and `<answer>` tags to separate reasoning from output.
- Ask Claude to self-check: "Before finishing, verify your answer against [criteria]."
- Use multishot examples with `<thinking>` tags to model the reasoning pattern.

---

## Agentic Systems

### Long-horizon reasoning and state tracking

Claude 4.6 excels at long-horizon tasks with exceptional state tracking:

- Maintains orientation across extended sessions
- Focuses on incremental progress
- Works across multiple context windows

### Context awareness

Claude 4.6 can track remaining context window. If your harness compacts context:

```
Your context window will be automatically compacted as it approaches its limit,
allowing you to continue working indefinitely. Do not stop tasks early due to
token budget concerns. Save progress before context refreshes. Be as persistent
and autonomous as possible.
```

### Multi-context window workflows

1. Use first context window to set up framework (write tests, create setup scripts)
2. Have Claude write tests in structured format (`tests.json`) before starting work
3. Set up quality-of-life tools (init.sh for servers, test suites, linters)
4. When context clears, prefer fresh start over compaction — Claude discovers state from filesystem
5. Provide verification tools (Playwright MCP, computer use)

### Balancing autonomy and safety

```
Consider reversibility and impact of actions. Take local, reversible actions
freely (editing files, running tests), but for hard-to-reverse or shared-system
actions, ask before proceeding.

Actions that warrant confirmation:
- Destructive: deleting files/branches, dropping tables, rm -rf
- Hard to reverse: force push, git reset --hard, amending published commits
- Visible to others: pushing code, commenting on PRs, sending messages
```

### Research and information gathering

```
Search for information in a structured way. Develop competing hypotheses.
Track confidence levels. Self-critique your approach. Update a research notes
file for transparency. Break down complex research systematically.
```

### Subagent orchestration

Claude 4.6 proactively delegates to subagents. Watch for overuse:

```
Use subagents when tasks can run in parallel, require isolated context, or
involve independent workstreams. For simple tasks, sequential operations, or
single-file edits, work directly rather than delegating.
```

### Minimize overengineering

Claude 4.6 tends to overengineer. Add explicit constraints:

```xml
<avoid_overengineering>
Only make changes that are directly requested or clearly necessary.

- Scope: Don't add features, refactor, or "improve" beyond what was asked.
- Documentation: Don't add docstrings or comments to code you didn't change.
- Defensive coding: Don't add error handling for scenarios that can't happen.
  Only validate at system boundaries (user input, external APIs).
- Abstractions: Don't create helpers for one-time operations. Don't design
  for hypothetical future requirements.
</avoid_overengineering>
```

### Avoid test-chasing and hard-coding

```
Write general-purpose solutions using standard tools. Do not hard-code values
or create solutions that only work for specific test inputs. Implement the
actual logic that solves the problem generally. If tests are incorrect, inform
me rather than working around them.
```

### Minimize hallucinations in agentic coding

```xml
<investigate_before_answering>
Never speculate about code you have not opened. If the user references a file,
read it before answering. Investigate relevant files BEFORE answering questions
about the codebase. Never make claims about code before investigating.
</investigate_before_answering>
```

---

## Migration: Older Models to Claude 4.6

| Change                     | Action                                                       |
| -------------------------- | ------------------------------------------------------------ |
| Prefills deprecated        | Use instructions, structured outputs, or XML tags instead    |
| `budget_tokens` deprecated | Use adaptive thinking with `effort` parameter                |
| More concise by default    | Explicitly request detail/summaries when needed              |
| Tools trigger more eagerly | Dial back aggressive language ("MUST", "CRITICAL", "ALWAYS") |
| More proactive             | Add safety guardrails for destructive actions                |
| Overthinking possible      | Use lower `effort` or add "commit to an approach" guidance   |

### Sonnet 4.5 to Sonnet 4.6

- Default effort is `high` (may increase latency). Set explicitly:
  - `medium` for most applications
  - `low` for high-volume / latency-sensitive workloads
- Set large max output token budget (64k recommended) at medium/high effort
- For hardest problems, use Opus 4.6 instead

---

## Quick Reference: Prompt Structure

Recommended hierarchy for complex system prompts:

```xml
<role>
Who Claude is and what it does
</role>

<constraints>
Non-negotiable rules (keep concise — Claude 4.6 follows instructions well,
no need for aggressive language)
</constraints>

<tone>
Communication style and voice
</tone>

<context>
Background information, documents, data
</context>

<instructions>
Step-by-step task flow
</instructions>

<examples>
<example>
<input>...</input>
<output>...</output>
</example>
</examples>

<tools>
Tool usage guidance
</tools>

<output_format>
Expected response structure
</output_format>
```

Place long documents/data ABOVE instructions. Place the immediate query/task at the END.
