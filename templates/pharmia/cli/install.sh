#!/usr/bin/env sh
# Install the Pharmia/Bento CLI toolkit (source of truth = this repo) onto PATH by
# symlinking each bin/* into a target dir. Idempotent. Used three ways:
#   - humans:   run directly, or automatically via the git post-merge/checkout hook
#   - Daytona:  CLI_INSTALL_DIR=/usr/local/bin sh install.sh   (in the image build)
# The scripts read their credentials from ~/.config/<tool>/ — those are NOT in this
# repo; on a dev box they already exist, in a sandbox they come from Vaultwarden
# (dev/qa-scoped). Editing a CLI = edit the file in bin/ here (the SSOT), then this
# install relinks it everywhere.
set -eu

HERE="$(cd "$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$0")")" && pwd)"
SRC="$HERE/bin"
TARGET="${CLI_INSTALL_DIR:-$HOME/.local/bin}"
BK="$TARGET/.cli-backup"
mkdir -p "$TARGET"

linked=0; skipped=0; backed=0
for f in "$SRC"/*; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  dest="$TARGET/$name"
  # already the correct symlink → nothing to do
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$f")" ]; then
    skipped=$((skipped + 1)); continue
  fi
  # a pre-existing real file (the dev's prior copy) → back it up once, then replace
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mkdir -p "$BK"; [ -e "$BK/$name" ] || cp -p "$dest" "$BK/$name"; rm -f "$dest"
    backed=$((backed + 1))
  fi
  ln -sfn "$f" "$dest"
  linked=$((linked + 1))
done

echo "[cli-install] target=$TARGET linked=$linked relinked-skipped=$skipped backed-up=$backed"
case ":${PATH}:" in
  *":$TARGET:"*) : ;;
  *) echo "[cli-install] NOTE: $TARGET is not on PATH — add: export PATH=\"$TARGET:\$PATH\"" ;;
esac
