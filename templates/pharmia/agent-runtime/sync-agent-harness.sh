#!/usr/bin/env bash
# Re-exec under bash if invoked via `sh script` (dash overrides the shebang and lacks
# `set -o pipefail`). Belt-and-suspenders so any caller is safe.
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
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
#   • CLIs (cli/bin/*) are deployed into /opt/bento-cli/bin — the FIRST dir on the agent's
#     PATH, so this is what `agent` actually executes. COPY (not symlink): the SSOT lives
#     under /home/ubuntu (mode 0750) which `agent` cannot traverse, so a symlink there would
#     dangle with EACCES; world-readable /opt copies do not. The deploy OWNS only the SSOT
#     basenames and prunes ones that vanished — foreign binaries (mcp-grafana, pgro,
#     agent-anthropic-key) are never in the SSOT set, so they are left untouched.
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

# 4) deploy the CLI toolkit into the PATH-first runtime dir (COPY, world-readable /opt —
#    the agent cannot traverse /home/ubuntu mode 0750, so symlinks-into-SSOT would EACCES).
#    rsync the SSOT bin/ in, then prune ONLY names this deploy previously OWNED that have
#    since vanished from the SSOT. The owned-set is persisted in a manifest, so foreign
#    binaries (mcp-grafana / pgro / agent-anthropic-key) — never written by us, never in the
#    manifest — are structurally unprunable.
CLI_SRC="$PHARMIA_DIR/cli/bin"
CLI_DST="/opt/bento-cli/bin"
CLI_MANIFEST="$CLI_DST/.bento-cli-manifest"
clis="?"
if [ -d "$CLI_SRC" ]; then
  sudo install -d -m 755 "$CLI_DST"
  # prune: anything in the PRIOR manifest that is no longer in the SSOT (and not foreign).
  if [ -f "$CLI_MANIFEST" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      [ -e "$CLI_SRC/$name" ] && continue            # still shipped → keep
      sudo rm -f "$CLI_DST/$name"                     # was ours, now gone → suppress
    done < <(sudo cat "$CLI_MANIFEST")
  fi
  sudo rsync -a "$CLI_SRC"/ "$CLI_DST"/               # copy/refresh every current SSOT cli
  sudo find "$CLI_DST" -maxdepth 1 -type f ! -name '.bento-cli-manifest' -exec chmod 0755 {} +  # ensure +x (vault-secret is 664 in SSOT)
  # rewrite manifest = the names we now own (current SSOT basenames).
  ls "$CLI_SRC" | sudo tee "$CLI_MANIFEST" >/dev/null
  sudo chmod 0644 "$CLI_MANIFEST"
  clis="$(sudo -u "$AGENT_USER" sh -c "ls \"$CLI_DST\" 2>/dev/null | grep -vc '^\.bento-cli-manifest$'")"
fi

echo "[sync-agent-harness] $AGENT_HOME/.claude refreshed — skills=$(sudo -u "$AGENT_USER" ls "$AGENT_HOME/.claude/skills" 2>/dev/null | wc -l), agents=$(sudo -u "$AGENT_USER" ls "$AGENT_HOME/.claude/agents" 2>/dev/null | wc -l), rules=$(sudo -u "$AGENT_USER" ls "$AGENT_HOME/.claude/rules" 2>/dev/null | wc -l), clis=$clis@$CLI_DST (memory + projects preserved)"
