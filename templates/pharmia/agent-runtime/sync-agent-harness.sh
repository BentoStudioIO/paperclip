#!/usr/bin/env bash
# sync-agent-harness.sh — refresh the LIVE `agent` runtime harness (/home/agent/.claude)
# from the paperclip SSOT. ONE canonical harness: renders the SSOT directly into the
# agent's home — there is NO parallel operator (ubuntu) harness to drift against.
# Idempotent; run as a sudoer (ubuntu has passwordless sudo on the agents VPS).
#
# Relationship to the other scripts (do not conflate):
#   • build.sh                    — bakes the SAME harness into the Coder workspace IMAGE
#                                   (renders + `docker build`). Coder reads the IMAGE, not
#                                   this host harness, so this script NEVER touches Coder.
#   • provision-agent-identity.sh — full one-time agent-user setup; its §6 calls THIS.
#   • .githooks/post-merge + the systemd timer — call THIS so a pull / a schedule keeps
#                                   /home/agent/.claude current with zero manual steps.
#
# Invariants:
#   • skills/ + agents/ are fully generated -> mirrored with --delete (prune removed ones).
#   • rules/ INCLUDES environment-bindings.md — this is a creds-injected runtime (unlike the
#     zero-creds Coder image, which build.sh strips it from).
#   • agent memory (~/.paperclip) and session history (~/.claude/projects) are PRESERVED
#     (never in the rsync scope).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"   # .../agent-runtime
PHARMIA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                       # .../templates/pharmia
REPO_ROOT="$(cd "$PHARMIA_DIR/../.." && pwd)"                     # paperclip repo root
AGENT_USER="${AGENT_USER:-agent}"
AGENT_HOME="/home/$AGENT_USER"

command -v node >/dev/null 2>&1 || { echo "[sync-agent-harness] node not found; cannot render" >&2; exit 1; }

# 1) refresh the SSOT (ff-only; never force). Best-effort: a detached/offline checkout
#    still re-syncs whatever is on disk.
git -C "$REPO_ROOT" pull --ff-only --quiet 2>/dev/null || true

# 2) render the claude harness under a THROWAWAY HOME (no docker, no clobber of any real
#    home, no rulesync fanout side effects on the operator's dotfiles).
RH="$(mktemp -d)"; trap 'rm -rf "$RH"' EXIT
HOME="$RH" node "$REPO_ROOT/scripts/sync-claude-agents.mjs" >/dev/null 2>&1 || true
HOME="$RH" node "$REPO_ROOT/scripts/sync-claude-skills.mjs"  >/dev/null 2>&1 || true

# 3) rsync into the ONE canonical harness (sudo: agent home is mode 700).
sudo install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 700 "$AGENT_HOME/.claude"
sudo install -d -o "$AGENT_USER" -g "$AGENT_USER" "$AGENT_HOME/.claude/rules"
[ -d "$RH/.claude/skills" ] && sudo rsync -a --delete "$RH/.claude/skills/" "$AGENT_HOME/.claude/skills/"
[ -d "$RH/.claude/agents" ] && sudo rsync -a --delete "$RH/.claude/agents/" "$AGENT_HOME/.claude/agents/"
sudo rsync -a "$PHARMIA_DIR/rules/"*.md "$AGENT_HOME/.claude/rules/" 2>/dev/null || true
# team CLAUDE.md — no-clobber (Claude Code loads ~/.claude/CLAUDE.md natively; don't stomp local edits)
[ -f "$AGENT_HOME/.claude/CLAUDE.md" ] || sudo cp -f "$SCRIPT_DIR/workspace-CLAUDE.md" "$AGENT_HOME/.claude/CLAUDE.md" 2>/dev/null || true
sudo chown -R "$AGENT_USER:$AGENT_USER" "$AGENT_HOME/.claude/skills" "$AGENT_HOME/.claude/agents" "$AGENT_HOME/.claude/rules" 2>/dev/null || true

echo "[sync-agent-harness] $AGENT_HOME/.claude refreshed — skills=$(sudo -u "$AGENT_USER" ls "$AGENT_HOME/.claude/skills" 2>/dev/null | wc -l), agents=$(sudo -u "$AGENT_USER" ls "$AGENT_HOME/.claude/agents" 2>/dev/null | wc -l), rules=$(sudo -u "$AGENT_USER" ls "$AGENT_HOME/.claude/rules" 2>/dev/null | wc -l) (memory + projects preserved)"
