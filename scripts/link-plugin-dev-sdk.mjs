#!/usr/bin/env node

import { existsSync, mkdirSync, lstatSync, readlinkSync, rmSync, symlinkSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const repoRoot = resolve(__dirname, "..");
const packageDir = process.cwd();
const sdkDir = join(repoRoot, "packages", "plugins", "sdk");
const scopeDir = join(packageDir, "node_modules", "@paperclipai");
const linkTarget = join(scopeDir, "plugin-sdk");

if (!existsSync(join(packageDir, "package.json"))) {
  throw new Error(`No package.json found in plugin directory: ${packageDir}`);
}

mkdirSync(scopeDir, { recursive: true });

try {
  const stat = lstatSync(linkTarget);
  if (stat.isSymbolicLink()) {
    rmSync(linkTarget, { force: true });
  } else {
    console.log("  i Keeping existing installed @paperclipai/plugin-sdk directory in place");
    process.exit(0);
  }
} catch {
  // target does not exist yet
}

const relativeSdkDir = relative(scopeDir, sdkDir);

try {
  symlinkSync(relativeSdkDir, linkTarget, "dir");
} catch (err) {
  // pnpm links the @paperclipai/plugin-sdk workspace dependency itself, and may
  // (re)create this symlink concurrently with this postinstall script — racing the
  // rm above and throwing EEXIST. Accept an existing symlink that already points at
  // the SDK as success; otherwise replace it.
  if (err?.code !== "EEXIST") throw err;
  const existing = lstatSync(linkTarget);
  if (existing.isSymbolicLink() && readlinkSync(linkTarget) === relativeSdkDir) {
    console.log(`  ✓ @paperclipai/plugin-sdk already linked for ${packageDir}`);
    process.exit(0);
  }
  rmSync(linkTarget, { force: true, recursive: true });
  symlinkSync(relativeSdkDir, linkTarget, "dir");
}

console.log(`  ✓ Linked local @paperclipai/plugin-sdk for ${packageDir}`);
