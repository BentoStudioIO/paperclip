#!/usr/bin/env bash
# One-command release for the Bento workspace stack (image + Coder template + shared devbox).
#
# Layers (all reproducible from this repo):
#   IMAGE    bento-agent-runtime — built by build.sh from the paperclip SSOT (binaries,
#            AI agents, team agents/skills in every harness format, tmux/screen).
#   TEMPLATE bento-workspace — template/main.tf (tiles, key injection, claude env parity,
#            startup logic, VS Code settings/extensions). Pushed with 4 SENSITIVE template
#            variables read from /etc/coder/* ON THE BOX (never from this repo).
#   VOLUME   per-workspace home — DERIVED state; self-assembles on first start. Only the
#            dev's own work is unique to it.
#
# Usage:
#   release.sh                  # push the template only (main.tf changes)
#   release.sh --image          # build + push image $(cat VERSION) + pre-pull on box, then template
#   release.sh --devbox         # ...and roll bentoadmin/devbox onto $(cat VERSION) (VOLUME PRESERVED)
#   release.sh --image --devbox # full pipeline
#
# Known traps this script encodes (cost real debug cycles — do not "simplify" them away):
#   * docker cp into an EXISTING container dir NESTS (coder-tpl/coder-tpl) → stale main.tf
#     silently pushed. Fix: rm -rf inside the container first.
#   * docker cp writes root-owned files; the coder CLI runs uid 1000 → chown before reading,
#     else the key vars are EMPTY and injection silently fail-closes.
#   * Template variables are PER-PUSH: omit one --variable and that injection turns off.
#   * workspace_image is a STORED per-workspace parameter; bumping the template default does
#     NOT migrate existing workspaces and `coder update --parameter` no-ops when the version
#     is current. The --devbox path POSTs a build with rich_parameter_values instead
#     (container recreated, home volume kept).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REGISTRY="git.bentostudio.io/bentostudio/bento-agent-runtime"
VERSION="$(cat "$SCRIPT_DIR/VERSION")"
BOX="agents"                          # ssh alias (ubuntu@149.56.13.177)
TEMPLATE_NAME="bento-workspace"
DEVBOX="bentoadmin/devbox"
KEYS=(anthropic-api-key openai-api-key groq-api-key opencode-zen-key)

WITH_IMAGE=0; WITH_DEVBOX=0
for a in "$@"; do case "$a" in
  --image) WITH_IMAGE=1 ;;
  --devbox) WITH_DEVBOX=1 ;;
  *) echo "unknown flag: $a (use --image / --devbox)"; exit 2 ;;
esac; done

say(){ printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }

# ── 1) image ──────────────────────────────────────────────────────────────────
if [ "$WITH_IMAGE" = 1 ]; then
  say "image: build $REGISTRY:$VERSION (local — never build on the 8GB box)"
  bash "$SCRIPT_DIR/build.sh"
  say "image: push $VERSION + latest"
  docker push "$REGISTRY:$VERSION"
  docker push "$REGISTRY:latest"
  say "image: pre-pull on $BOX (instant workspace starts; registry_auth covers it anyway)"
  ssh "$BOX" "sudo docker pull $REGISTRY:$VERSION" >/dev/null
fi

# ── 2) template ───────────────────────────────────────────────────────────────
say "template: stage $TEMPLATE_NAME (fresh dirs — host AND container, see nesting trap)"
ssh "$BOX" 'sudo rm -rf /tmp/coder-tpl && mkdir -p /tmp/coder-tpl'
scp -q "$SCRIPT_DIR/coder/template/main.tf" "$BOX:/tmp/coder-tpl/"

say "template: push with the 4 sensitive variables (keys live ONLY on the box)"
ssh "$BOX" 'sudo bash -c "
  set -euo pipefail
  TK=\$(cat /etc/coder/owner-token)
  docker exec -u 0 coder rm -rf /tmp/coder-tpl
  docker cp /tmp/coder-tpl coder:/tmp/coder-tpl
  for k in '"${KEYS[*]}"'; do
    docker cp /etc/coder/\$k coder:/tmp/\$k
    docker exec -u 0 coder chown 1000:1000 /tmp/\$k
  done
  docker exec -e CODER_URL=http://localhost:7080 -e CODER_SESSION_TOKEN=\$TK coder \
    sh -c '\''coder templates push '"$TEMPLATE_NAME"' -d /tmp/coder-tpl \
      --variable anthropic_api_key=\"\$(cat /tmp/anthropic-api-key)\" \
      --variable openai_api_key=\"\$(cat /tmp/openai-api-key)\" \
      --variable groq_api_key=\"\$(cat /tmp/groq-api-key)\" \
      --variable opencode_zen_api_key=\"\$(cat /tmp/opencode-zen-key)\" \
      --yes 2>&1 | tail -2'\''
  docker exec -u 0 coder sh -c \"rm -f /tmp/anthropic-api-key /tmp/openai-api-key /tmp/groq-api-key /tmp/opencode-zen-key\"
"'

# ── 3) shared devbox ─────────────────────────────────────────────────────────
if [ "$WITH_DEVBOX" = 1 ]; then
  say "devbox: roll $DEVBOX onto $REGISTRY:$VERSION via API build (home volume preserved)"
  ssh "$BOX" 'sudo bash -c "
    set -euo pipefail
    TK=\$(cat /etc/coder/owner-token)
    WS_ID=\$(curl -s -H \"Coder-Session-Token: \$TK\" \"http://127.0.0.1:7080/api/v2/workspaces?q=owner:bentoadmin+name:devbox\" \
      | python3 -c \"import json,sys; print(json.load(sys.stdin)[\\\"workspaces\\\"][0][\\\"id\\\"])\")
    # Pin the build to the ACTIVE template version — a build POST without
    # template_version_id reuses the workspace'"'"'s pinned (old) version and the new
    # startup logic never runs (cost a debug cycle).
    TV_ID=\$(curl -s -H \"Coder-Session-Token: \$TK\" \"http://127.0.0.1:7080/api/v2/workspaces?q=owner:bentoadmin+name:devbox\" \
      | python3 -c \"import json,sys; print(json.load(sys.stdin)[\\\"workspaces\\\"][0][\\\"template_active_version_id\\\"])\")
    curl -s -X POST -H \"Coder-Session-Token: \$TK\" -H \"Content-Type: application/json\" \
      \"http://127.0.0.1:7080/api/v2/workspaces/\$WS_ID/builds\" \
      -d \"{\\\"transition\\\":\\\"start\\\",\\\"template_version_id\\\":\\\"\$TV_ID\\\",\\\"rich_parameter_values\\\":[{\\\"name\\\":\\\"workspace_image\\\",\\\"value\\\":\\\"'"$REGISTRY:$VERSION"'\\\"}]}\" \
      | python3 -c \"import json,sys; d=json.load(sys.stdin); print(\\\"build:\\\", d.get(\\\"status\\\", d))\"
    for i in \$(seq 1 60); do
      docker ps --format \"{{.Names}}\" | grep -q coder-bentoadmin-devbox && break; sleep 5
    done
    sleep 10
    echo image-now: \$(docker inspect coder-bentoadmin-devbox --format \"{{.Config.Image}}\")
  "'
fi

say "DONE. template=$TEMPLATE_NAME image=$REGISTRY:$VERSION$( [ $WITH_DEVBOX = 1 ] && echo ' devbox=rolled' )"
