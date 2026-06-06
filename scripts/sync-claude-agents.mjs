#!/usr/bin/env node
/**
 * sync-claude-agents.mjs — project Paperclip agent definitions into Claude Code subagents.
 *
 * Paperclip is the single source of truth. Each `templates/pharmia/agents/<slug>/AGENTS.md`
 * carries two stacked frontmatter blocks: block 1 is Paperclip orchestration metadata
 * (name/title/reportsTo/skills), block 2 is a verbatim Claude Code subagent frontmatter
 * (name/description/model/tools…) followed by the prompt body. This script extracts the
 * Claude block + body and writes `~/.claude/agents/<name>.md`, so pulling the repo keeps
 * the local subagents in sync with zero hand-editing.
 *
 * Generated files are tagged with `source: paperclip` in frontmatter (and a " (synced from
 * Paperclip)" suffix on the description). That tag is the prune key: stale generated files
 * are removed on the next run, while hand-authored personal agents (no tag) are never touched.
 *
 * Usage:
 *   node scripts/sync-claude-agents.mjs [--dry-run] [--verbose]
 * Env:
 *   CLAUDE_AGENTS_DIR   override target dir (default: ~/.claude/agents)
 */

import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync, rmSync, statSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { homedir } from "node:os";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(__dirname, "..");
const SRC_DIR = join(repoRoot, "templates", "pharmia", "agents");
const TARGET_DIR = process.env.CLAUDE_AGENTS_DIR || join(homedir(), ".claude", "agents");
const MARKER = "source: paperclip";
const DESC_SUFFIX = " (synced from Paperclip)";

const argv = new Set(process.argv.slice(2));
const DRY = argv.has("--dry-run");
const VERBOSE = argv.has("--verbose");

/** Positions of full-line `---` fences. */
function fenceLineRanges(text) {
  const fences = [];
  const re = /^---[ \t]*$/gm;
  let m;
  while ((m = re.exec(text)) !== null) fences.push(m.index);
  return fences;
}

/**
 * Returns the Claude-format slice (the frontmatter block containing `description:` onward,
 * including the body) or null if the file has no Claude block.
 */
function extractClaudeSlice(text) {
  const fences = fenceLineRanges(text);
  if (fences.length < 2) return null;
  // Walk fence pairs as frontmatter blocks; pick the one whose body has a description: key.
  for (let i = 0; i + 1 < fences.length; i += 2) {
    const openStart = fences[i];
    const innerStart = text.indexOf("\n", openStart) + 1;
    const closeStart = fences[i + 1];
    const block = text.slice(innerStart, closeStart);
    if (/^description:/m.test(block)) {
      return text.slice(openStart); // from this block's opening fence to EOF (verbatim body)
    }
  }
  return null;
}

/** Inject the paperclip marker + description suffix into a Claude-format slice. */
function tagSlice(slice) {
  const fences = fenceLineRanges(slice);
  const fmInnerStart = slice.indexOf("\n", fences[0]) + 1;
  const fmClose = fences[1];
  let fm = slice.slice(fmInnerStart, fmClose);
  const body = slice.slice(fmClose); // includes closing fence + body, verbatim

  // Append suffix to the description value if not already present (idempotent vs clean source).
  fm = fm.replace(/^(description:\s*)(.*)$/m, (_, k, v) =>
    v.includes(DESC_SUFFIX.trim()) ? `${k}${v}` : `${k}${v}${DESC_SUFFIX}`,
  );
  // Prepend the marker key if absent.
  if (!new RegExp(`^${MARKER}$`, "m").test(fm)) fm = `${MARKER}\n${fm}`;

  return `---\n${fm}${body}`;
}

function nameFromSlice(slice) {
  const m = slice.match(/^name:\s*["']?([^"'\n]+)["']?\s*$/m);
  return m ? m[1].trim() : null;
}

function isGenerated(filePath) {
  try {
    const head = readFileSync(filePath, "utf8").slice(0, 600);
    return new RegExp(`^${MARKER}$`, "m").test(head);
  } catch {
    return false;
  }
}

// ---- build the generated set ----
if (!existsSync(SRC_DIR)) {
  console.error(`[sync-claude-agents] source dir not found: ${SRC_DIR}`);
  process.exit(1);
}

const generated = new Map(); // filename -> content
const skipped = [];
for (const entry of readdirSync(SRC_DIR)) {
  const agentMd = join(SRC_DIR, entry, "AGENTS.md");
  if (!existsSync(agentMd) || !statSync(agentMd).isFile()) continue;
  const text = readFileSync(agentMd, "utf8");
  const slice = extractClaudeSlice(text);
  if (!slice) {
    skipped.push(`${entry} (no Claude/description frontmatter block)`);
    continue;
  }
  const name = nameFromSlice(slice) || entry;
  generated.set(`${name}.md`, tagSlice(slice));
}

// ---- write ----
if (!existsSync(TARGET_DIR)) {
  if (DRY) console.log(`[dry-run] would mkdir ${TARGET_DIR}`);
  else mkdirSync(TARGET_DIR, { recursive: true });
}

let written = 0;
let unchanged = 0;
for (const [file, content] of generated) {
  const dest = join(TARGET_DIR, file);
  const prev = existsSync(dest) ? readFileSync(dest, "utf8") : null;
  if (prev === content) {
    unchanged++;
    if (VERBOSE) console.log(`  = ${file} (unchanged)`);
    continue;
  }
  if (DRY) console.log(`  ${prev === null ? "+ create" : "~ update"} ${file}`);
  else writeFileSync(dest, content);
  written++;
}

// ---- prune stale generated files (tagged but no longer in source) ----
let pruned = 0;
if (existsSync(TARGET_DIR)) {
  for (const file of readdirSync(TARGET_DIR)) {
    if (!file.endsWith(".md") || generated.has(file)) continue;
    const dest = join(TARGET_DIR, file);
    if (!isGenerated(dest)) continue; // never touch hand-authored personal agents
    if (DRY) console.log(`  - prune ${file}`);
    else rmSync(dest);
    pruned++;
  }
}

console.log(
  `[sync-claude-agents] ${DRY ? "(dry-run) " : ""}target=${TARGET_DIR} | ` +
    `${generated.size} sources, ${written} written, ${unchanged} unchanged, ${pruned} pruned` +
    (skipped.length ? ` | skipped: ${skipped.join(", ")}` : ""),
);
