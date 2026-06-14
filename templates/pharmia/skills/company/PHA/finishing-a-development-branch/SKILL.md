---
name: finishing-a-development-branch
description: Use when implementation is complete, all tests pass, and you need to decide how to integrate the work - guides completion of development work by presenting structured options for merge, PR, or cleanup
---

# Finishing a Development Branch

## Overview

Guide completion of development work by presenting clear options and handling chosen workflow.

**Core principle:** Verify tests → Present options → Execute choice → Clean up.

**Announce at start:** "I'm using the finishing-a-development-branch skill to complete this work."

## The Process

### Step 1: Verify Tests

**Before presenting options, verify tests pass:**

```bash
# Run project's test suite
npm test / cargo test / pytest / go test ./...
```

**If tests fail:**
```
Tests failing (<N> failures). Must fix before completing:

[Show failures]

Cannot proceed with merge/PR until tests pass.
```

Stop. Don't proceed to Step 2.

**If tests pass:** Continue to Step 2.

### Step 2: Determine Base Branch

```bash
# Try common base branches
git merge-base HEAD main 2>/dev/null || git merge-base HEAD master 2>/dev/null
```

Or ask: "This branch split from main - is that correct?"

### Step 3: Present Options

Present exactly these 4 options:

```
Implementation complete. What would you like to do?

1. Merge back to <base-branch> locally
2. Push and create a Pull Request
3. Keep the branch as-is (I'll handle it later)
4. Discard this work

Which option?
```

**Don't add explanation** - keep options concise.

### Step 4: Execute Choice

#### Option 1: Merge Locally

```bash
# Switch to base branch
git checkout <base-branch>

# Pull latest
git pull

# Merge feature branch
git merge <feature-branch>

# Verify tests on merged result
<test command>

# If tests pass
git branch -d <feature-branch>
```

Then: Cleanup worktree (Step 5)

#### Option 2: Push and Create PR

```bash
# Push branch
git push -u origin <feature-branch>

# Create PR
gh pr create --title "<title>" --body "$(cat <<'EOF'
## Summary
<2-3 bullets of what changed>

## Test Plan
- [ ] <verification steps>
EOF
)"
```

Then: Cleanup worktree (Step 5)

#### Option 3: Keep As-Is

Only when work is genuinely incomplete and will resume in THIS branch, with a real owner who returns to it. Not a parking spot for finished work — finished work takes Option 1 or 2; abandoned work takes Option 4.

Report: "Keeping branch <name>, worktree at <path> — work in progress, will resume."

**Don't cleanup worktree.** For an autonomous agent with no "later," a kept branch/worktree IS abandonment — choose Option 1, 2, or 4 instead.

#### Option 4: Discard

**Confirm first:**
```
This will permanently delete:
- Branch <name>
- All commits: <commit-list>
- Worktree at <path>

Type 'discard' to confirm.
```

Wait for exact confirmation.

If confirmed:
```bash
git checkout <base-branch>
git branch -D <feature-branch>
```

Then: Cleanup worktree (Step 5)

### Step 5: Cleanup Worktree

**For Options 1, 2, 4:**

Check if in worktree:
```bash
git worktree list | grep $(git branch --show-current)
```

If yes:
```bash
git worktree remove <worktree-path>
```

**For Option 3:** Keep worktree.

### Step 6: No Stale Artifacts (definition of done)

Worktrees and branches are encouraged for isolation — but they are task-scoped, not durable. At completion, the repo must carry no artifact you created that no longer has an owner:

- **Worth keeping → commit on a named branch** (push if durability matters). Never leave worth-keeping work as a dangling stash or an orphaned worktree.
- **Stashes:** prefer a commit on a named branch over `git stash`; drop any stash you created (`git stash drop`) — a stash is a private, unlabelled buffer, not a handoff.
- **Branches:** delete once merged (Option 1) or abandoned (Option 4); don't leave dead WIP branches.
- **Worktrees:** `git worktree remove <path>` then `git worktree prune`.

An orphaned worktree, an un-merged abandoned branch, or a leftover stash at task end is **incomplete work** — a defect to resolve before declaring done.

## Quick Reference

| Option | Merge | Push | Keep Worktree | Cleanup Branch |
|--------|-------|------|---------------|----------------|
| 1. Merge locally | ✓ | - | - | ✓ |
| 2. Create PR | - | ✓ | ✓ | - |
| 3. Keep as-is (WIP only) | - | - | ✓ | - |
| 4. Discard | - | - | - | ✓ (force) |

## Common Mistakes

**Skipping test verification**
- **Problem:** Merge broken code, create failing PR
- **Fix:** Always verify tests before offering options

**Open-ended questions**
- **Problem:** "What should I do next?" → ambiguous
- **Fix:** Present exactly 4 structured options

**Automatic worktree cleanup**
- **Problem:** Remove worktree when might need it (Option 2, 3)
- **Fix:** Only cleanup for Options 1 and 4

**No confirmation for discard**
- **Problem:** Accidentally delete work
- **Fix:** Require typed "discard" confirmation

## Red Flags

**Never:**
- Proceed with failing tests
- Merge without verifying tests on result
- Delete work without confirmation
- Force-push without explicit request

**Always:**
- Verify tests before offering options
- Present exactly 4 options
- Get typed confirmation for Option 4
- Clean up worktree for Options 1 & 4 only
- Leave no stale artifact you created — orphaned worktree, dead branch, or stray stash = incomplete work

## Integration

**Called by:**
- **subagent-driven-development** (Step 7) - After all tasks complete
- **executing-plans** (Step 5) - After all batches complete

**Pairs with:**
- **using-git-worktrees** - Cleans up worktree created by that skill

<!-- Evolution: 2026-06-14 | evidence: a local PharmaMate clone had accumulated 3 worktrees (2 abandoned isolation:worktree spikes), 21 stale stashes (labelled "preserved before worktree removal"/"aborted"/"unrelated", ~2wk old), and dead WIP branches from prior autonomous sessions — no lost work, but it manufactured "did we drift?" confusion and cost a cleanup session. The teardown gate sanctioned abandonment: Option 3 was a consequence-free park-it option and no step pruned stashes or required deleting dead branches. | tightened Option 3 to WIP-only-with-owner; added Step 6 No Stale Artifacts (commit-not-stash; remove+prune worktree; delete dead branch; drop stashes; leftover = defect); added Red-Flags line. -->
