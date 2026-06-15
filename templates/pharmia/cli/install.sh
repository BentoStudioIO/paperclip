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

# If invoked from a LINKED git worktree, link to the PRIMARY worktree's bin instead
# — the canonical symlinks must never point into a throwaway worktree (deleting it
# would dangle every CLI). A linked worktree's git-dir is <main>/.git/worktrees/<name>,
# so the main worktree root is everything before "/.git/worktrees/". No-op in Daytona
# / outside a repo. Belt-and-suspenders to the post-checkout/post-merge hook guards.
if command -v git >/dev/null 2>&1; then
  _gd="$(git -C "$HERE" rev-parse --absolute-git-dir 2>/dev/null || true)"
  case "$_gd" in
    */.git/worktrees/*)
      _main="${_gd%/.git/worktrees/*}"
      [ -d "$_main/templates/pharmia/cli/bin" ] && SRC="$_main/templates/pharmia/cli/bin"
      ;;
  esac
fi

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

# Opt-in pruning (CLI_PRUNE=1): suppress CLIs removed from the SSOT. Inherently safe —
# only ever removes farm-owned SYMLINKS whose resolved target lives under THIS run's SRC
# dir but whose basename no longer exists in SRC. Foreign real-file binaries (e.g. a
# compiled mcp-grafana dropped into the same dir) are never symlinks-into-SRC, so they
# are structurally untouchable. Off by default so a human install to ~/.local/bin never
# surprise-deletes a hand-placed tool.
pruned=0
if [ "${CLI_PRUNE:-0}" = "1" ]; then
  SRC_RESOLVED="$(readlink -f "$SRC")"
  for dest in "$TARGET"/*; do
    [ -L "$dest" ] || continue                       # only symlinks are farm-owned
    tgt="$(readlink -f "$dest" 2>/dev/null || true)"
    case "$tgt" in
      "$SRC_RESOLVED"/*) ;;                            # points into our SRC bin → ours
      *) continue ;;                                   # foreign symlink → leave alone
    esac
    [ -e "$SRC/$(basename "$dest")" ] && continue      # still in SSOT → keep
    rm -f "$dest"; pruned=$((pruned + 1))
  done
fi

echo "[cli-install] target=$TARGET linked=$linked relinked-skipped=$skipped backed-up=$backed pruned=$pruned"
case ":${PATH}:" in
  *":$TARGET:"*) : ;;
  *) echo "[cli-install] NOTE: $TARGET is not on PATH — add: export PATH=\"$TARGET:\$PATH\"" ;;
esac
