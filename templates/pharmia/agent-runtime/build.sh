#!/usr/bin/env bash
# Deterministic build of the Pharmia agent-runtime Coder workspace image.
#
# Renders the TEAM engineering agents + skills from the paperclip SSOT
# (templates/pharmia/{agents,skills}) into a gitignored build-context staging dir, then
# builds the image for linux/amd64. The staging dir is REGENERATED every run so the image
# always reflects the current SSOT — no generated files are committed.
#
# Usage:
#   templates/pharmia/agent-runtime/build.sh [VERSION]
#     VERSION  image version tag (default: read from VERSION file beside this script)
#
# Tags built: git.bentostudio.io/bentostudio/bento-agent-runtime:<VERSION> and :latest
# Push separately:  docker login git.bentostudio.io && docker push <ref>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"   # .../agent-runtime
PHARMIA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                       # .../templates/pharmia
REPO_ROOT="$(cd "$PHARMIA_DIR/../.." && pwd)"                     # paperclip repo root
REGISTRY="git.bentostudio.io/bentostudio/bento-agent-runtime"
VERSION="${1:-$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "0.0.0-dev")}"
STAGE="$SCRIPT_DIR/.claude-config-staging"

echo "==> rendering team agents/skills/rules from SSOT into $STAGE (all harness formats)"
rm -rf "$STAGE"
mkdir -p "$STAGE/agents" "$STAGE/skills" "$STAGE/rules" "$STAGE/codex" "$STAGE/opencode" "$STAGE/agents-std"
# Render under a THROWAWAY HOME (NOT CLAUDE_AGENTS_DIR) so the sync scripts run their
# rulesync fanout — CLAUDE_AGENTS_DIR is the exact flag that SKIPS rulesync. One pass
# emits every harness format: ~/.claude, ~/.codex, ~/.config/opencode, ~/.agents.
RENDER_HOME="$SCRIPT_DIR/.render-home"
rm -rf "$RENDER_HOME"; mkdir -p "$RENDER_HOME"
HOME="$RENDER_HOME" node "$REPO_ROOT/scripts/sync-claude-agents.mjs"
HOME="$RENDER_HOME" node "$REPO_ROOT/scripts/sync-claude-skills.mjs"
# Collect each produced tree into the staging dir the Dockerfile bakes. The .claude
# layout (agents/skills/rules) is kept IDENTICAL so the startup .claude sync is unchanged.
cp -r "$RENDER_HOME/.claude/agents/." "$STAGE/agents/" 2>/dev/null || true
cp -r "$RENDER_HOME/.claude/skills/." "$STAGE/skills/" 2>/dev/null || true
cp -f "$PHARMIA_DIR/rules/"*.md "$STAGE/rules/" 2>/dev/null || true
# environment-bindings.md is written for the CREDS-INJECTED paperclip sandbox; in zero-creds
# Coder workspaces it makes Claude over-claim toolkit access. Excluded from the image —
# runtimes that inject scoped creds (Daytona/paperclip) should supply it themselves.
rm -f "$STAGE/rules/environment-bindings.md"
# env-dump deny-hook (leak backstop): workspaces carry the gateway token + free-model keys
# in env; this PreToolUse hook blocks reflexive env/secret-file dumps from landing in Claude
# transcripts. Wired into ~/.claude/settings.json by the template startup (see main.tf).
mkdir -p "$STAGE/hooks"
cp -f "$SCRIPT_DIR/hooks/deny-env-dump.sh" "$STAGE/hooks/deny-env-dump.sh" && chmod 755 "$STAGE/hooks/deny-env-dump.sh"
# Team CLAUDE.md (engineering discipline distilled from the CTO's guide) — synced to
# ~/.claude/CLAUDE.md by the template startup (no-clobber; Claude Code loads it natively).
cp -f "$SCRIPT_DIR/workspace-CLAUDE.md" "$STAGE/CLAUDE.md"
cp -r "$RENDER_HOME/.codex/." "$STAGE/codex/" 2>/dev/null || true             # -> ~/.codex
cp -r "$RENDER_HOME/.config/opencode/." "$STAGE/opencode/" 2>/dev/null || true # -> ~/.config/opencode
cp -r "$RENDER_HOME/.agents/." "$STAGE/agents-std/" 2>/dev/null || true        # -> ~/.agents (agentskills.io)
rm -rf "$RENDER_HOME"
echo "==> staged: $(ls "$STAGE/agents" 2>/dev/null | wc -l) claude-agents, $(ls "$STAGE/skills" 2>/dev/null | wc -l) skills, $(ls "$STAGE/codex/agents" 2>/dev/null | wc -l) codex-agents, $(ls "$STAGE/opencode/agents" 2>/dev/null | wc -l) opencode-agents, $(ls "$STAGE/agents-std/skills" 2>/dev/null | wc -l) agentskills"

echo "==> building $REGISTRY:$VERSION (+ :latest) for linux/amd64"
docker build --platform linux/amd64 \
  -f "$SCRIPT_DIR/Dockerfile" \
  -t "$REGISTRY:$VERSION" \
  -t "$REGISTRY:latest" \
  "$PHARMIA_DIR"

echo "==> built $REGISTRY:$VERSION and $REGISTRY:latest"
echo "    push with: docker push $REGISTRY:$VERSION && docker push $REGISTRY:latest"
