#!/usr/bin/env bash
# Claude Code PreToolUse hook (matcher: Bash) — backstop that keeps reflexive
# environment / secret-file dumps out of run transcripts.
#
# Defense-in-depth: the PRIMARY control is that the agent environment no longer
# carries broad secrets (fetched on demand from Vault via `vault-secret`). This
# hook blocks the common ways a tool call would still spill the env or a creds
# file verbatim into the JSONL transcript. Precise patterns only — it must not
# block legitimate work (e.g. `env FOO=bar cmd`, `set -euo pipefail`, `printenv ONE_VAR`).
#
# stdin : {"tool_name":"Bash","tool_input":{"command":"..."}}
# stdout: a PreToolUse permissionDecision JSON object.
#
# FAIL-OPEN by construction: this is a backstop, not the primary control (the
# primary control is that the agent env carries no broad secrets). It never uses
# `set -e`, so any hiccup (missing jq, odd input) falls through to `allow` rather
# than blocking every Bash call the agent makes.

input="$(cat 2>/dev/null || true)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
norm="$(printf '%s' "$cmd" | tr '\n\t' '  ')"

deny() {
  local reason="$1"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' \
    "$(printf '%s' "$reason" | jq -Rsa .)"
  exit 0
}
allow() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}\n'; exit 0; }

GUIDE="Dumping the environment or a creds file into the transcript is blocked (secret-leak guard). Fetch the single value you need with: vault-secret <KEY>."

# bare `env` / `printenv` / `set` as a standalone command (start-of-line or after ; | &),
# NOT env-as-launcher (`env FOO=bar cmd`, `env -i cmd`) or `printenv ONE_VAR` or `set -e`.
if printf '%s' "$norm" | grep -qE '(^|[;|&]+)[[:space:]]*(/usr/bin/)?env[[:space:]]*($|[;|&])'; then deny "$GUIDE"; fi
if printf '%s' "$norm" | grep -qE '(^|[;|&]+)[[:space:]]*printenv[[:space:]]*($|[;|&])'; then deny "$GUIDE"; fi
if printf '%s' "$norm" | grep -qE '(^|[;|&]+)[[:space:]]*set[[:space:]]*($|[;|&])'; then deny "$GUIDE"; fi

# explicit whole-environment dumps
if printf '%s' "$norm" | grep -qE '\b(export[[:space:]]+-p|declare[[:space:]]+-x|typeset[[:space:]]+-x|compgen[[:space:]]+-v|getconf[[:space:]]+-a)\b'; then deny "$GUIDE"; fi

# reading shell-init / env / proc-environ files verbatim
if printf '%s' "$norm" | grep -qE '([./]zsh(env|rc)|[./]zprofile|/\.env([[:space:]"'"'"';|&]|$)|/proc/([0-9]+|self|thread-self)/environ)'; then deny "$GUIDE"; fi

# reading the Vault / Forgejo credential files
if printf '%s' "$norm" | grep -qE '\.config/(pharmia-vault|forgejo)/'; then deny "$GUIDE"; fi

allow
