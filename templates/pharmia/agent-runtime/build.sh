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
# Tags built: git.bentostudio.io/bentostudio/pharmia-agent-runtime:<VERSION> and :latest
# Push separately:  docker login git.bentostudio.io && docker push <ref>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"   # .../agent-runtime
PHARMIA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"                       # .../templates/pharmia
REPO_ROOT="$(cd "$PHARMIA_DIR/../.." && pwd)"                     # paperclip repo root
REGISTRY="git.bentostudio.io/bentostudio/pharmia-agent-runtime"
VERSION="${1:-$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "0.0.0-dev")}"
STAGE="$SCRIPT_DIR/.claude-config-staging"

echo "==> rendering team agents/skills/rules from SSOT into $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/agents" "$STAGE/skills" "$STAGE/rules"
CLAUDE_AGENTS_DIR="$STAGE/agents" node "$REPO_ROOT/scripts/sync-claude-agents.mjs"
CLAUDE_SKILLS_DIR="$STAGE/skills" node "$REPO_ROOT/scripts/sync-claude-skills.mjs"
cp -f "$PHARMIA_DIR/rules/"*.md "$STAGE/rules/" 2>/dev/null || true
echo "==> staged: $(ls "$STAGE/agents" | wc -l) agents, $(ls "$STAGE/skills" | wc -l) skills, $(ls "$STAGE/rules" | wc -l) rules"

echo "==> building $REGISTRY:$VERSION (+ :latest) for linux/amd64"
docker build --platform linux/amd64 \
  -f "$SCRIPT_DIR/Dockerfile" \
  -t "$REGISTRY:$VERSION" \
  -t "$REGISTRY:latest" \
  "$PHARMIA_DIR"

echo "==> built $REGISTRY:$VERSION and $REGISTRY:latest"
echo "    push with: docker push $REGISTRY:$VERSION && docker push $REGISTRY:latest"
