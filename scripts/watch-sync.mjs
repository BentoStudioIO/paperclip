#!/usr/bin/env node
// watch-sync — instant Paperclip → local autosync.
//
// Watches the Pharmia agent + skill TEMPLATES and re-runs the local sync
// (templates → ~/.claude, the same scripts the git post-merge hook runs) on
// every change, debounced. So editing a template reflects in your Claude Code
// environment immediately — no `git pull`, no manual `node scripts/sync-*.mjs`.
//
// Direction is one-way (Paperclip is SSOT → ~/.claude). It does NOT push local
// edits back; edit the template, not the generated `~/.claude` copy.
//
// Runs `--no-rulesync` for speed (instant ~/.claude write, no network/npx); the
// full codex/opencode rulesync fanout still happens on `git pull` via .githooks.
//
// Run manually: `node scripts/watch-sync.mjs`  (Ctrl-C to stop)
// Or as a durable systemd user service — see AGENTS.md §15.
import { watch } from "node:fs";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const targets = [
  path.join(repo, "templates/pharmia/agents"),
  path.join(repo, "templates/pharmia/skills"),
];
const SCRIPTS = ["sync-claude-agents.mjs", "sync-claude-skills.mjs"];
const DEBOUNCE_MS = 400;

let timer = null;
let running = false;
let pending = false;

function runSync(reason) {
  if (running) {
    pending = true;
    return;
  }
  running = true;
  console.log(`[autosync] ${new Date().toISOString()} sync (${reason})`);
  let i = 0;
  const next = () => {
    if (i >= SCRIPTS.length) {
      running = false;
      if (pending) {
        pending = false;
        schedule("queued");
      } else {
        console.log("[autosync] up to date");
      }
      return;
    }
    const s = SCRIPTS[i++];
    const child = spawn(process.execPath, [path.join(repo, "scripts", s), "--no-rulesync"], {
      cwd: repo,
      stdio: "inherit",
    });
    child.on("exit", next);
    child.on("error", (e) => {
      console.error(`[autosync] ${s} failed:`, e.message);
      running = false;
    });
  };
  next();
}

function schedule(reason) {
  clearTimeout(timer);
  timer = setTimeout(() => runSync(reason), DEBOUNCE_MS);
}

for (const dir of targets) {
  try {
    watch(dir, { recursive: true }, (_evt, file) => schedule(file || path.basename(dir)));
    console.log("[autosync] watching", dir);
  } catch (e) {
    console.error("[autosync] cannot watch", dir, "—", e.message);
  }
}

runSync("startup");
process.on("SIGINT", () => {
  console.log("\n[autosync] stopped");
  process.exit(0);
});
