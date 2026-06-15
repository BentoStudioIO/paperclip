#!/usr/bin/env bash
# Provision the capped `agent` execution identity on the agents VPS (Paperclip's
# claude_local SSH target). IDEMPOTENT — safe to re-run; converges to the intended
# state. This is the SSOT for the hand-applied setup so a fresh VPS / home volume
# reseeds (per PLAN-shared-agent-vps.md + memory paperclip-agent-identity).
#
# Run ON the agents VPS as a sudoer (e.g. `ssh bento-agents 'sudo bash provision-agent-identity.sh'`).
# Harness (~/.claude) is rendered fresh from the SSOT by agent-runtime/sync-agent-harness.sh
# (§6 below) — the SAME script the post-merge hook + systemd timer use to keep it current.
#
# SECRETS: never hardcoded. Required token files/creds are read from env vars; a line
# is only (re)written when its env var is set, otherwise the existing value is preserved
# (so re-running live without secrets in env is a no-op for those lines). Source them
# from Vaultwarden / the ~/.config escrow before running a FRESH provision:
#   FORGEJO_TOKEN              (bentoadmin site-admin token — required)
#   AGENT_GATEWAY_TOKEN        (LiteLLM virtual key for CLAUDE_CODE_OAUTH_TOKEN)
#   PG_DEV_PASSWORD PG_QA_PASSWORD LOKI_DEV_TOKEN LOKI_QA_TOKEN LOKI_CANARY_TOKEN
#   DISCORD_BOT_TOKEN          (Paperclip Discord bot token for `discord-post` back-posts;
#                              SAME bot 1515174537153482843 as the plugin — so awoken
#                              assignment agents reply from the Paperclip bot)
#   GRAFANA_TOKEN_DEV GRAFANA_TOKEN_QA OUTLINE_API_TOKEN CLOUDFLARE_API_TOKEN  (optional)
set -euo pipefail

AGENT_USER=agent
AGENT_HOME=/home/$AGENT_USER
BENTO_EGRESS_IP="${BENTO_EGRESS_IP:-51.222.204.73}"          # Paperclip control-plane egress
ENV_PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgTH1DrhC+JNKSh8m/ehFUyKZgRE90zjK6d1/qakNTf pharmia-agents-ops"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGING_DIR="${STAGING_DIR:-$SCRIPT_DIR/.claude-config-staging}"
GATEWAY_URL="${ANTHROPIC_BASE_URL:-https://llm.bentostudio.io}"
FORGEJO_URL="${FORGEJO_URL:-https://git.bentostudio.io}"

log(){ printf '  • %s\n' "$*"; }
as_agent(){ sudo -u "$AGENT_USER" "$@"; }

echo "== 1) agent user (capped, zsh, no sudo) =="
if ! id "$AGENT_USER" &>/dev/null; then
  sudo useradd -m -s /usr/bin/zsh "$AGENT_USER"; log "created $AGENT_USER"
fi
sudo gpasswd -d "$AGENT_USER" sudo 2>/dev/null || true     # strip any default sudo
sudo install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 700 "$AGENT_HOME/.ssh" "$AGENT_HOME/.config" "$AGENT_HOME/workspaces"
log "user present, no sudo, ~/.ssh ~/.config ~/workspaces ensured"

echo "== 2) inbound SSH: only the Paperclip env key, locked to the control-plane IP =="
AK="$AGENT_HOME/.ssh/authorized_keys"
printf 'from="%s" %s\n' "$BENTO_EGRESS_IP" "$ENV_PUBKEY" | sudo tee "$AK" >/dev/null
sudo chown "$AGENT_USER:$AGENT_USER" "$AK"; sudo chmod 600 "$AK"
log "authorized_keys = env key from=$BENTO_EGRESS_IP (single key, source-locked)"
# NOTE: outbound keys (~/.ssh/{bento,pharmia-qa,prod-ro} + config) are per-host identities
# restored from escrow — not regenerated here (would break the authorized principals).
# The `prod-ro` alias (HostName 167.114.2.32, User pg-ro, forced-command
# `sudo /usr/local/bin/canary-pg-ro-query`) is what powers READ-ONLY canary access:
# `pg canary app|mastra` detects this box has `prod-ro` but no full `prod` alias and
# routes through it (SELECT-only, NOSUPERUSER). Do NOT add `PG_CANARY_*` here — the
# RO path needs no client-side canary password (it lives root-only on prod). If a
# fresh box lacks the `prod-ro` alias/key in escrow, `pg canary` RO will not work
# until the escrowed ssh identity is restored.

echo "== 3) ~/.profile sources ~/.zshenv (the ssh driver sources *profile, NOT zshenv) =="
PROFILE="$AGENT_HOME/.profile"
sudo touch "$PROFILE"; sudo chown "$AGENT_USER:$AGENT_USER" "$PROFILE"
if ! sudo grep -q 'zshenv' "$PROFILE"; then
  printf '\n# Paperclip ssh runs sh: pull the scoped agent env in\n[ -f ~/.zshenv ] && . ~/.zshenv\n' | sudo tee -a "$PROFILE" >/dev/null
  log "appended zshenv sourcing"
fi

echo "== 4) Forgejo token (SSOT file) + git credential helper + identity =="
CFG="$AGENT_HOME/.config/forgejo"
sudo install -d -o "$AGENT_USER" -g "$AGENT_USER" -m 700 "$CFG"
if [ -n "${FORGEJO_TOKEN:-}" ]; then
  printf '%s' "$FORGEJO_TOKEN" | sudo tee "$CFG/token" >/dev/null
  sudo chown "$AGENT_USER:$AGENT_USER" "$CFG/token"; sudo chmod 600 "$CFG/token"; log "wrote token file"
elif ! sudo test -s "$CFG/token"; then
  echo "  ! FORGEJO_TOKEN not set and $CFG/token absent — Forgejo git will fail"; fi
sudo tee "$CFG/git-credential-bentoadmin" >/dev/null <<'HELPER'
#!/bin/sh
[ "$1" = "get" ] || exit 0
echo username=bentoadmin
echo "password=$(cat /home/agent/.config/forgejo/token)"
HELPER
sudo chown "$AGENT_USER:$AGENT_USER" "$CFG/git-credential-bentoadmin"; sudo chmod 750 "$CFG/git-credential-bentoadmin"
as_agent git config --global user.name  bentoadmin
as_agent git config --global user.email bentoadmin@bentostudio.io
as_agent git config --global "credential.$FORGEJO_URL.helper" "$CFG/git-credential-bentoadmin"
log "git helper bound to $FORGEJO_URL"

echo "== 5) ~/.zshenv: structural lines + secrets (only when provided in env) =="
ZE="$AGENT_HOME/.zshenv"
sudo touch "$ZE"; sudo chown "$AGENT_USER:$AGENT_USER" "$ZE"; sudo chmod 600 "$ZE"
ensure_line(){ local k="$1" line="$2"; sudo grep -q "^export $k=" "$ZE" || echo "$line" | sudo tee -a "$ZE" >/dev/null; }
# Atomic upsert into the SHARED ~/.zshenv: render the full new file to a temp and mv
# it into place (atomic rename, same fs) instead of a non-atomic `sed -i` + `tee -a`.
# The old two-step raced when secrets were ensured back-to-back/concurrently on the
# shared file — a partial sed/tee interleave dropped or corrupted lines.
ensure_secret(){
  local k="$1" v="${2:-}"; [ -n "$v" ] || return 0
  local tmp="${ZE}.tmp.$$"
  { sudo grep -v "^export $k=" "$ZE" 2>/dev/null || true; echo "export $k=$v"; } | sudo tee "$tmp" >/dev/null
  sudo chown "$AGENT_USER:$AGENT_USER" "$tmp"; sudo chmod 600 "$tmp"; sudo mv -f "$tmp" "$ZE"
}
# guards (dash-safe; the ssh driver runs sh, not zsh)
sudo grep -q 'ZSH_VERSION.*_bun' "$ZE" || true   # bun completion is guarded at author time
ensure_line FORGEJO_URL "export FORGEJO_URL=\"$FORGEJO_URL\""
sudo grep -q 'config/forgejo/token' "$ZE" || echo '[ -r ~/.config/forgejo/token ] && export FORGEJO_TOKEN="$(cat ~/.config/forgejo/token)"' | sudo tee -a "$ZE" >/dev/null
ensure_line ANTHROPIC_BASE_URL "export ANTHROPIC_BASE_URL=\"$GATEWAY_URL\""
# Gateway token MUST stay in env: Claude Code authenticates to the llm.bentostudio.io
# gateway via `Authorization: Bearer` (CLAUDE_CODE_OAUTH_TOKEN). apiKeyHelper only delivers
# an x-api-key, which the gateway rejects ("Ensure Key has Bearer prefix"), so it cannot be
# moved out of the env. It stays here, protected by the env-dump deny-hook installed in §6c.
ensure_secret CLAUDE_CODE_OAUTH_TOKEN "${AGENT_GATEWAY_TOKEN:-}"
# 2026-06-15 leak fix: the tool secrets (PG_*, LOKI_*, GRAFANA_TOKEN_*, OUTLINE_API_TOKEN,
# CLOUDFLARE_API_TOKEN, DISCORD_BOT_TOKEN) are NO LONGER injected into the agent env — an
# `env`/`printenv` dump used to persist them verbatim into run transcripts. The wrapper CLIs
# (pg/loki/prom/ol/cfdns/discord-post) now fetch each value ON DEMAND from HashiCorp Vault
# secret/agents/* via `vault-secret`, so the env carries none of them. See §6c for the
# bootstrap (read-only agents-ro AppRole creds) + the deny-hook. To rotate a value, update
# Vault (secret/agents/<name>), NOT this file. GH_TOKEN/GITHUB_PERSONAL_ACCESS_TOKEN remain
# in env for the compiled `gh`; FORGEJO_TOKEN is already file-sourced above.
sudo chmod 600 "$ZE"; log "zshenv: gateway token + structural lines only; tool secrets are Vault-fetched on demand (§6c)"

echo "== 6) harness ~/.claude (single canonical agent harness) =="
# DRY: the ONE harness-sync codepath, shared with the post-merge hook + systemd timer.
# Renders the SSOT fresh into /home/agent/.claude (no docker, no staging dependency).
AGENT_USER="$AGENT_USER" bash "$SCRIPT_DIR/sync-agent-harness.sh" \
  || echo "  ! harness sync failed (node/repo?) — re-run $SCRIPT_DIR/sync-agent-harness.sh"

echo "== 6b) harness auto-sync timer (keeps /home/agent/.claude current; also the hook's marker) =="
sudo cp "$SCRIPT_DIR/paperclip-agent-harness.service" "$SCRIPT_DIR/paperclip-agent-harness.timer" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now paperclip-agent-harness.timer >/dev/null 2>&1 \
  && log "harness timer enabled (6h backstop; post-merge hook keys off /etc/systemd/system/paperclip-agent-harness.service)" \
  || echo "  ! could not enable paperclip-agent-harness.timer"

echo "== 6c) leak-prevention: Vault-fetch CLI toolkit + env-dump deny-hook (2026-06-15) =="
# Tool secrets are fetched on demand from HashiCorp Vault (secret/agents/*) by the wrapper
# CLIs via `vault-secret`, instead of sitting in the agent env where an env dump leaked them
# into run transcripts. Bootstrap = a READ-ONLY, secret/agents/*-scoped AppRole (agents-ro)
# whose role_id/secret_id live in a 0600 file OUTSIDE the env. Idempotent; survives the
# harness sync (settings.json + hooks/ are not in sync-agent-harness.sh's rsync scope).
CLI_SRC="$(cd "$SCRIPT_DIR/../cli/bin" 2>/dev/null && pwd)"
if [ -n "$CLI_SRC" ]; then
  sudo install -d -m 755 /opt/bento-cli/bin
  sudo install -m 755 "$CLI_SRC"/* /opt/bento-cli/bin/ 2>/dev/null \
    && log "installed CLI toolkit (incl vault-secret + Vault-fallback pg/loki/prom/ol/cfdns/discord-post) into /opt/bento-cli/bin"
fi
# agents-ro Vault creds (read-only). role_id/secret_id sourced from escrow env before provisioning.
if [ -n "${AGENT_VAULT_RO_ROLE_ID:-}" ] && [ -n "${AGENT_VAULT_RO_SECRET_ID:-}" ]; then
  sudo -u "$AGENT_USER" install -d -m 700 "$AGENT_HOME/.config/pharmia-vault"
  printf 'VAULT_RO_ROLE_ID=%s\nVAULT_RO_SECRET_ID=%s\n' "$AGENT_VAULT_RO_ROLE_ID" "$AGENT_VAULT_RO_SECRET_ID" \
    | sudo -u "$AGENT_USER" tee "$AGENT_HOME/.config/pharmia-vault/agents-ro.env" >/dev/null
  sudo chmod 600 "$AGENT_HOME/.config/pharmia-vault/agents-ro.env"; log "wrote agents-ro Vault creds (0600, outside the env)"
elif ! sudo test -s "$AGENT_HOME/.config/pharmia-vault/agents-ro.env"; then
  echo "  ! AGENT_VAULT_RO_{ROLE,SECRET}_ID unset and creds absent — vault-secret (and the Vault-fetch CLIs) will fail until provided"
fi
# env-dump deny-hook (PreToolUse, matcher Bash): backstop so a reflexive env/printenv/secret-file
# dump can't land in a transcript. Fail-open by construction (never blocks all Bash).
sudo -u "$AGENT_USER" install -d -m 700 "$AGENT_HOME/.claude/hooks"
sudo install -o "$AGENT_USER" -g "$AGENT_USER" -m 750 "$SCRIPT_DIR/hooks/deny-env-dump.sh" "$AGENT_HOME/.claude/hooks/deny-env-dump.sh"
printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/home/agent/.claude/hooks/deny-env-dump.sh"}]}]}}' \
  | sudo -u "$AGENT_USER" tee "$AGENT_HOME/.claude/settings.json" >/dev/null
sudo chmod 600 "$AGENT_HOME/.claude/settings.json"
log "env-dump deny-hook + settings.json installed (verified to enforce under --dangerously-skip-permissions)"

echo "== 7) host: ssh banner-off + ufw allow for the control-plane IP =="
sudo tee /etc/ssh/sshd_config.d/99-paperclip-no-banner.conf >/dev/null <<EOF
Match Address $BENTO_EGRESS_IP
    Banner none
EOF
sudo grep -qE "^AllowUsers.*\b$AGENT_USER\b" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null \
  || echo "  ! ensure sshd AllowUsers includes '$AGENT_USER' (left to host policy)"
sudo sshd -t && sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true
command -v ufw >/dev/null && sudo ufw insert 1 allow from "$BENTO_EGRESS_IP" to any port 22 proto tcp >/dev/null 2>&1 || true
log "banner suppressed + ufw rate-limit bypass for $BENTO_EGRESS_IP"

echo "== 8) per-agent memory dir + MCP servers (grafana read-only + context7) =="
# AGENT_HOME is set PER-AGENT in Paperclip (agents.adapter_config.env.AGENT_HOME =
# /home/agent/.paperclip/agents/<id>) so para-memory-files persists on this durable home.
sudo -u "$AGENT_USER" mkdir -p "$AGENT_HOME/.paperclip/agents"
# mcp-grafana binary (read-only) on the agent PATH (/opt/bento-cli is world-readable + on PATH)
if [ ! -x /opt/bento-cli/bin/mcp-grafana ]; then
  curl -fsSL "https://github.com/grafana/mcp-grafana/releases/download/v0.15.2/mcp-grafana_Linux_x86_64.tar.gz" \
    | sudo tar -xz -C /opt/bento-cli/bin mcp-grafana && sudo chmod 755 /opt/bento-cli/bin/mcp-grafana
fi
# The live SSH run reads /home/agent/.claude.json NATIVELY (no --mcp-config; NOT the build staging).
# Literal creds: claude 2.1.x does not expand ${VAR} at MCP spawn. Token read from env, never committed.
if [ -n "${GRAFANA_TOKEN_DEV:-}" ]; then
  sudo -u "$AGENT_USER" env GU="${GRAFANA_URL_DEV:-https://grafana.dev.pharmia.ca}" GT="$GRAFANA_TOKEN_DEV" python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude.json")
try: d = json.load(open(p))
except Exception: d = {}
d.setdefault("mcpServers", {})
d["mcpServers"]["grafana"]  = {"command":"mcp-grafana","args":["-t","stdio","--disable-write"],
                               "env":{"GRAFANA_URL":os.environ["GU"],"GRAFANA_SERVICE_ACCOUNT_TOKEN":os.environ["GT"]}}
d["mcpServers"]["context7"] = {"command":"npx","args":["-y","@upstash/context7-mcp"]}
json.dump(d, open(p,"w"), indent=2)
print("  mcpServers:", list(d["mcpServers"]))
PY
  sudo chmod 600 "$AGENT_HOME/.claude.json"
else
  echo "  ! GRAFANA_TOKEN_DEV unset — skipped grafana MCP (set it to provision the read-only grafana server)"
fi

echo "== 9) standing bento-docs reference clone + daily ff-only refresh cron =="
# Bento Studio's durable legal/compliance/TGV SSOT (verbatim primary sources). Cloned AS
# the `agent` user so the Forgejo bentoadmin credential helper (step 4) authenticates and
# files stay agent-owned. Idempotent: pull --ff-only if already cloned, else fresh clone.
# The harness awareness rule ships in rules/bento-docs.md (synced into ~/.claude/rules above).
BENTO_DOCS_DIR="$AGENT_HOME/bento-docs"
BENTO_DOCS_URL="$FORGEJO_URL/BentoStudio/bento-docs.git"
if sudo test -d "$BENTO_DOCS_DIR/.git"; then
  as_agent git -C "$BENTO_DOCS_DIR" pull --ff-only >/dev/null 2>&1 \
    && log "bento-docs present — pulled --ff-only" \
    || echo "  ! bento-docs pull failed (check Forgejo token / network) — leaving existing clone"
else
  as_agent git clone "$BENTO_DOCS_URL" "$BENTO_DOCS_DIR" >/dev/null 2>&1 \
    && log "cloned bento-docs -> $BENTO_DOCS_DIR (as $AGENT_USER)" \
    || echo "  ! bento-docs clone failed (FORGEJO_TOKEN unset/invalid?) — skipped"
fi
# Daily ff-only refresh as `agent` (verbatim from the live box). HOME=/home/agent so the
# global git config + credential helper resolve for the cron user.
sudo tee /etc/cron.d/bento-docs-refresh >/dev/null <<'CRON'
# Daily ff-only refresh of the standing bento-docs reference clone (Paperclip agents read it).
# Runs as `agent` so the Forgejo bentoadmin credential helper authenticates and files stay agent-owned.
SHELL=/bin/sh
PATH=/usr/local/bin:/usr/bin:/bin
HOME=/home/agent
17 6 * * * agent git -C /home/agent/bento-docs pull --ff-only >> /home/agent/bento-docs/.refresh.log 2>&1
CRON
sudo chmod 644 /etc/cron.d/bento-docs-refresh
log "installed /etc/cron.d/bento-docs-refresh (daily 06:17 ff-only pull as $AGENT_USER)"

echo "== DONE — agent identity provisioned/converged =="
