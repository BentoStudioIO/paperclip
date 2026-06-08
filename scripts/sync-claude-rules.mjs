#!/usr/bin/env node
/**
 * sync-claude-rules.mjs — project Paperclip-owned rules into Claude Code's global rules dir,
 * then fan out to codex + opencode via rulesync. Companion to sync-claude-agents.mjs and
 * sync-claude-skills.mjs.
 *
 * Paperclip is the single source of truth for sandbox-relevant rules (currently just the
 * agent-sandbox `environment-bindings.md`). `~/.claude/rules/` is the portable primary target;
 * rulesync then mirrors to codex/opencode where present. Rules are plain markdown with no YAML
 * frontmatter, so the prune marker is an HTML comment on line 1: `<!-- source: paperclip -->`.
 * Generated files carrying that marker are pruned when they leave source; hand-authored rules
 * (no marker) are never touched.
 *
 * Usage:  node scripts/sync-claude-rules.mjs [--dry-run] [--verbose] [--no-rulesync]
 * Env:    CLAUDE_RULES_DIR  override target (default ~/.claude/rules); RULESYNC_TARGETS
 */

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { spawnSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..");
const SRC_DIR = join(repoRoot, "templates", "pharmia", "rules");
const TARGET_DIR = process.env.CLAUDE_RULES_DIR || join(homedir(), ".claude", "rules");
const MARKER = "<!-- source: paperclip -->";

const argv = new Set(process.argv.slice(2));
const DRY = argv.has("--dry-run");
const VERBOSE = argv.has("--verbose");

if (!existsSync(SRC_DIR)) { console.error(`[sync-claude-rules] source dir not found: ${SRC_DIR}`); process.exit(1); }

// ---- build generated set (tag each with the prune marker on line 1) ----
const generated = new Map();
for (const name of readdirSync(SRC_DIR)) {
  if (!name.endsWith(".md")) continue;
  const body = readFileSync(join(SRC_DIR, name), "utf8").replace(/^<!-- source: paperclip -->\n/, "");
  generated.set(name, `${MARKER}\n${body}`);
}

if (!existsSync(TARGET_DIR) && !DRY) mkdirSync(TARGET_DIR, { recursive: true });
let written = 0, unchanged = 0, skippedHandAuthored = 0;
for (const [name, content] of generated) {
  const dest = join(TARGET_DIR, name);
  const prev = existsSync(dest) ? readFileSync(dest, "utf8") : null;
  // NEVER clobber a hand-authored rule (no prune marker). The host's full
  // ~/.claude/rules/environment-bindings.md is the user's hand-authored reference,
  // NOT Paperclip-generated — the trimmed sandbox copy must not overwrite it.
  if (prev !== null && !prev.startsWith(MARKER)) {
    skippedHandAuthored++;
    if (VERBOSE) console.log(`  ! skip hand-authored ${name} (not overwriting)`);
    continue;
  }
  if (prev === content) { unchanged++; if (VERBOSE) console.log(`  = ${name}`); continue; }
  if (DRY) { console.log(`  ${prev === null ? "+ create" : "~ update"} ${name}`); written++; continue; }
  writeFileSync(dest, content);
  written++;
}

// ---- prune stale generated rules (marker present but no longer in source) ----
let pruned = 0;
for (const name of existsSync(TARGET_DIR) ? readdirSync(TARGET_DIR) : []) {
  if (!name.endsWith(".md") || generated.has(name)) continue;
  const dest = join(TARGET_DIR, name);
  if (!readFileSync(dest, "utf8").startsWith(MARKER)) continue;
  if (DRY) console.log(`  - prune ${name}`);
  else rmSync(dest, { force: true });
  pruned++;
}

console.log(
  `[sync-claude-rules] ${DRY ? "(dry-run) " : ""}target=${TARGET_DIR} | ` +
    `${generated.size} sources, ${written} written, ${unchanged} unchanged, ${skippedHandAuthored} hand-authored-skipped, ${pruned} pruned`,
);

// ---- fan out to codex + opencode via rulesync (best-effort; the "sync everywhere" tool) ----
if (!argv.has("--no-rulesync") && !process.env.CLAUDE_RULES_DIR) {
  const targets = process.env.RULESYNC_TARGETS || "codexcli,opencode";
  const rsArgs = ["-y", "rulesync@latest", "convert", "--from", "claudecode", "--to", targets,
    "--features", "rules", "--global", VERBOSE ? "--verbose" : "--silent"];
  if (DRY) rsArgs.push("--dry-run");
  try {
    const r = spawnSync("npx", rsArgs, { stdio: VERBOSE ? "inherit" : "ignore" });
    console.log(`[sync-claude-rules] rulesync rules -> ${targets}: ${r.status === 0 ? "ok" : `skipped (exit ${r.status})`}`);
  } catch (e) {
    console.log(`[sync-claude-rules] rulesync skipped: ${e.message}`);
  }
}
