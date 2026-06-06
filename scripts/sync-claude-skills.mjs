#!/usr/bin/env node
/**
 * sync-claude-skills.mjs — project Paperclip company skills into the shared skills store.
 *
 * Companion to sync-claude-agents.mjs. Paperclip is the single source of truth. On this
 * machine all harnesses share ONE skills store: `~/.agents/skills/` (the AGENTS.md skills
 * convention), symlinked in by each harness:
 *   ~/.claude/skills/<name>        -> ../../.agents/skills/<name>   (per-skill symlinks)
 *   ~/.codex/skills                -> ~/.agents/skills              (whole-dir symlink)
 *   ~/.config/opencode/skills      -> ~/.agents/skills              (whole-dir symlink)
 * So writing a skill into the store reaches all three at once — no per-harness conversion
 * (no rulesync) needed for skills, unlike agents.
 *
 * This copies each `templates/pharmia/skills/**​/<slug>/SKILL.md` (+ support files) into the
 * store, rewriting SKILL.md to strip Paperclip-internal frontmatter keys (slug/metadata/key)
 * and tag it `source: paperclip`. It then ensures the per-skill `~/.claude/skills/<name>`
 * symlink exists. Reference-only stubs (empty body / `description: ">"`) are skipped.
 *
 * The `source: paperclip` tag is the prune key: stale generated skills are removed from the
 * store (and their .claude symlink); skills.sh / hand-authored skills (no tag) are untouched.
 *
 * Usage:  node scripts/sync-claude-skills.mjs [--dry-run] [--verbose]
 * Env:    AGENTS_SKILLS_DIR (store, default ~/.agents/skills), CLAUDE_SKILLS_DIR (links, default ~/.claude/skills)
 */

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync, rmSync, cpSync, lstatSync, symlinkSync, readlinkSync } from "node:fs";
import { join, dirname, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..");
const SRC_DIR = join(repoRoot, "templates", "pharmia", "skills");
const STORE_DIR = process.env.AGENTS_SKILLS_DIR || join(homedir(), ".agents", "skills");
const LINK_DIR = process.env.CLAUDE_SKILLS_DIR || join(homedir(), ".claude", "skills");
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
  return `${MARKER}\n${out.join("\n").replace(/^\n+/, "")}`;
}

/** Ensure LINK_DIR/<name> is a symlink to ../../.agents/skills/<name>. */
function ensureClaudeLink(name) {
  const link = join(LINK_DIR, name);
  const target = relative(LINK_DIR, join(STORE_DIR, name));
  if (existsSync(link) || (() => { try { lstatSync(link); return true; } catch { return false; } })()) {
    try {
      const st = lstatSync(link);
      if (st.isSymbolicLink() && readlinkSync(link) === target) return false; // already correct
      if (DRY) { console.log(`    link ~> ${name} (replace)`); return true; }
      rmSync(link, { recursive: true, force: true });
    } catch { /* fallthrough to create */ }
  }
  if (DRY) { console.log(`    link +> ${name}`); return true; }
  symlinkSync(target, link);
  return true;
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

// ---- write into store + ensure .claude symlink ----
if (!DRY) { mkdirSync(STORE_DIR, { recursive: true }); mkdirSync(LINK_DIR, { recursive: true }); }
let written = 0, unchanged = 0, linked = 0;
for (const [name, { srcDir, skillMd }] of generated) {
  const dest = join(STORE_DIR, name);
  const destMd = join(dest, "SKILL.md");
  const prev = existsSync(destMd) ? readFileSync(destMd, "utf8") : null;
  if (prev !== skillMd || !existsSync(dest)) {
    if (DRY) console.log(`  ${prev === null ? "+ create" : "~ update"} ${name}/`);
    else { cpSync(srcDir, dest, { recursive: true, dereference: true }); writeFileSync(destMd, skillMd); }
    written++;
  } else { unchanged++; if (VERBOSE) console.log(`  = ${name}`); }
  if (ensureClaudeLink(name)) linked++;
}

// ---- prune stale generated skills (tagged but no longer in source) ----
let pruned = 0;
if (existsSync(STORE_DIR)) {
  for (const name of readdirSync(STORE_DIR)) {
    const md = join(STORE_DIR, name, "SKILL.md");
    if (generated.has(name) || !existsSync(md)) continue;
    if (!new RegExp(`^${MARKER}$`, "m").test(readFileSync(md, "utf8").slice(0, 600))) continue;
    if (DRY) console.log(`  - prune ${name}/`);
    else { rmSync(join(STORE_DIR, name), { recursive: true, force: true }); try { rmSync(join(LINK_DIR, name), { recursive: true, force: true }); } catch {} }
    pruned++;
  }
}

console.log(
  `[sync-claude-skills] ${DRY ? "(dry-run) " : ""}store=${STORE_DIR} | ` +
    `${generated.size} sources, ${written} written, ${unchanged} unchanged, ${linked} (re)linked, ${pruned} pruned` +
    (skipped.length ? ` | skipped ${skipped.length} stub(s)` : ""),
);
console.log(`[sync-claude-skills] codex + opencode share the store via whole-dir symlink — no rulesync needed.`);
