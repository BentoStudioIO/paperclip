#!/usr/bin/env node
/**
 * sync-claude-skills.mjs — project Paperclip company skills into Claude Code skills, then
 * fan out to codex + opencode via rulesync. Companion to sync-claude-agents.mjs.
 *
 * Paperclip is the single source of truth. `~/.claude/skills/` is the portable primary target
 * (every dev machine has it); rulesync then mirrors to codex/opencode where present. Skills are
 * directories, so each `templates/pharmia/skills/**​/<slug>/SKILL.md` (+ support files) is copied
 * to `~/.claude/skills/<name>/` as a REAL dir (replacing any pre-existing symlink), with SKILL.md
 * rewritten to strip Paperclip-internal frontmatter keys (slug/metadata/key) and tagged
 * `source: paperclip`. Reference-only stubs (empty body / `description: ">"`) are skipped.
 *
 * The `source: paperclip` tag is the prune key: stale generated skills are removed; hand-authored
 * / skills.sh skills (no tag) are never touched.
 *
 * Usage:  node scripts/sync-claude-skills.mjs [--dry-run] [--verbose] [--no-rulesync]
 * Env:    CLAUDE_SKILLS_DIR  override target (default ~/.claude/skills); RULESYNC_TARGETS
 */

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync, rmSync, cpSync, lstatSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";
import { spawnSync } from "node:child_process";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..");
const SRC_DIR = join(repoRoot, "templates", "pharmia", "skills");
const TARGET_DIR = process.env.CLAUDE_SKILLS_DIR || join(homedir(), ".claude", "skills");
const MARKER = "source: paperclip";
const STRIP_KEYS = new Set(["slug", "metadata", "key", "source"]);

const argv = new Set(process.argv.slice(2));
const DRY = argv.has("--dry-run");
const VERBOSE = argv.has("--verbose");

function findSkillFiles(dir, acc = []) {
  if (!existsSync(dir)) return acc;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) findSkillFiles(p, acc);
    else if (e.name === "SKILL.md") acc.push(p);
  }
  return acc;
}

function splitFrontmatter(text) {
  const m = /^---[ \t]*\n([\s\S]*?)\n---[ \t]*\n?([\s\S]*)$/.exec(text);
  return m ? { fm: m[1], body: m[2] } : null;
}

function field(fm, key) {
  const m = new RegExp(`^${key}:\\s*(.*)$`, "m").exec(fm);
  return m ? m[1].trim().replace(/^["']|["']$/g, "") : null;
}

function cleanFrontmatter(fm) {
  const out = [];
  let skipping = false;
  for (const line of fm.split("\n")) {
    const top = /^([A-Za-z][\w-]*):/.exec(line);
    if (top) { skipping = STRIP_KEYS.has(top[1]); if (!skipping) out.push(line); }
    else if (!skipping) out.push(line);
  }
  let result = out.join("\n").replace(/^\n+/, "");
  // Normalize comma-string list fields to YAML arrays — Claude tolerates the string form
  // but rulesync's strict (Zod) schema requires an array (e.g. spec-miner's allowed-tools).
  result = result.replace(
    /^(allowed-tools|tools):[ \t]*["']?([^"'\n][^"'\n]*?)["']?[ \t]*$/gm,
    (_, k, v) => `${k}:\n${v.split(",").map((s) => s.trim()).filter(Boolean).map((i) => `  - "${i}"`).join("\n")}`,
  );
  return `${MARKER}\n${result}`;
}

function pathExists(p) { try { lstatSync(p); return true; } catch { return false; } }

// Relative paths of every file under `dir` (recursive), excluding the top-level SKILL.md
// (which is rewritten separately). Used to detect reference/support-file-only edits.
function listSupportFiles(dir, base = dir, acc = []) {
  if (!existsSync(dir)) return acc;
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) listSupportFiles(p, base, acc);
    else { const rel = p.slice(base.length + 1); if (rel !== "SKILL.md") acc.push(rel); }
  }
  return acc;
}

// Whether dest already holds byte-identical copies of every non-SKILL.md file in srcDir
// (and no extra/missing ones). cpSync copies these verbatim, so a plain Buffer compare is valid.
function supportFilesMatch(srcDir, dest) {
  const src = listSupportFiles(srcDir).sort();
  const dst = listSupportFiles(dest).sort();
  if (src.length !== dst.length || src.some((f, i) => f !== dst[i])) return false;
  for (const f of src) {
    try { if (!readFileSync(join(srcDir, f)).equals(readFileSync(join(dest, f)))) return false; }
    catch { return false; }
  }
  return true;
}

function isGenerated(dir) {
  try { return new RegExp(`^${MARKER}$`, "m").test(readFileSync(join(dir, "SKILL.md"), "utf8").slice(0, 600)); }
  catch { return false; }
}

if (!existsSync(SRC_DIR)) { console.error(`[sync-claude-skills] source dir not found: ${SRC_DIR}`); process.exit(1); }

// ---- build generated set ----
const generated = new Map();
const skipped = [];
for (const file of findSkillFiles(SRC_DIR)) {
  const parts = splitFrontmatter(readFileSync(file, "utf8"));
  if (!parts) { skipped.push(`${file} (no frontmatter)`); continue; }
  const name = field(parts.fm, "name");
  const desc = field(parts.fm, "description");
  if (!name || !desc || desc === ">" || parts.body.trim().length === 0) { skipped.push(name || file); continue; }
  generated.set(name, { srcDir: dirname(file), skillMd: `---\n${cleanFrontmatter(parts.fm)}\n---\n${parts.body}` });
}

// ---- write as REAL dirs (replace any pre-existing symlink/dir) ----
if (!existsSync(TARGET_DIR) && !DRY) mkdirSync(TARGET_DIR, { recursive: true });
let written = 0, unchanged = 0;
for (const [name, { srcDir, skillMd }] of generated) {
  const dest = join(TARGET_DIR, name);
  const destMd = join(dest, "SKILL.md");
  // Only treat as "unchanged" when dest is a real dir whose SKILL.md already matches.
  const isRealDir = pathExists(dest) && lstatSync(dest).isDirectory() && !lstatSync(dest).isSymbolicLink();
  const prev = isRealDir && existsSync(destMd) ? readFileSync(destMd, "utf8") : null;
  if (prev === skillMd && supportFilesMatch(srcDir, dest)) { unchanged++; if (VERBOSE) console.log(`  = ${name}`); continue; }
  if (DRY) { console.log(`  ${pathExists(dest) ? "~ update" : "+ create"} ${name}/`); written++; continue; }
  if (pathExists(dest)) rmSync(dest, { recursive: true, force: true }); // drop stale symlink or dir
  cpSync(srcDir, dest, { recursive: true, dereference: true });
  writeFileSync(destMd, skillMd);
  written++;
}

// ---- prune stale generated skills (tagged but no longer in source) ----
let pruned = 0;
for (const name of existsSync(TARGET_DIR) ? readdirSync(TARGET_DIR) : []) {
  const dest = join(TARGET_DIR, name);
  if (generated.has(name) || !existsSync(join(dest, "SKILL.md")) || !isGenerated(dest)) continue;
  if (DRY) console.log(`  - prune ${name}/`);
  else rmSync(dest, { recursive: true, force: true });
  pruned++;
}

console.log(
  `[sync-claude-skills] ${DRY ? "(dry-run) " : ""}target=${TARGET_DIR} | ` +
    `${generated.size} sources, ${written} written, ${unchanged} unchanged, ${pruned} pruned` +
    (skipped.length ? ` | skipped ${skipped.length} stub(s)` : ""),
);

// ---- fan out to codex + opencode via rulesync (best-effort; the "sync everywhere" tool) ----
if (!argv.has("--no-rulesync") && !process.env.CLAUDE_SKILLS_DIR) {
  const targets = process.env.RULESYNC_TARGETS || "codexcli,opencode";
  const rsArgs = ["-y", "rulesync@latest", "convert", "--from", "claudecode", "--to", targets,
    "--features", "skills", "--global", VERBOSE ? "--verbose" : "--silent"];
  if (DRY) rsArgs.push("--dry-run");
  try {
    const r = spawnSync("npx", rsArgs, { stdio: VERBOSE ? "inherit" : "ignore" });
    console.log(`[sync-claude-skills] rulesync skills -> ${targets}: ${r.status === 0 ? "ok" : `skipped (exit ${r.status})`}`);
  } catch (e) {
    console.log(`[sync-claude-skills] rulesync skipped: ${e.message}`);
  }
}
