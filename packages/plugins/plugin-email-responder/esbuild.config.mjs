import esbuild from "esbuild";
import { createPluginBundlerPresets } from "@paperclipai/plugin-sdk/bundlers";

// No UI surface for this plugin — only the worker + manifest are bundled. The
// worker preset bundles third-party deps (imapflow, the Anthropic SDK) into
// dist/worker.js so the host can run it as a standalone ESM module.
const presets = createPluginBundlerPresets({});
const watch = process.argv.includes("--watch");

// imapflow is CommonJS and dynamically `require()`s Node built-ins (tls, net,
// crypto, …). esbuild bundles the worker as ESM, where `require` is undefined,
// so those dynamic requires throw "Dynamic require of \"tls\" is not supported"
// at runtime. Inject a module-scoped `require` via createRequire so the shim
// resolves built-ins through Node's native loader. (Built-ins stay external on
// platform:node, so only the `require` symbol needs to exist.)
const workerOptions = {
  ...presets.esbuild.worker,
  banner: {
    js: "import { createRequire as __pcCreateRequire } from 'node:module';\nconst require = __pcCreateRequire(import.meta.url);",
  },
};

const workerCtx = await esbuild.context(workerOptions);
const manifestCtx = await esbuild.context(presets.esbuild.manifest);

if (watch) {
  await Promise.all([workerCtx.watch(), manifestCtx.watch()]);
  console.log("esbuild watch mode enabled for worker and manifest");
} else {
  await Promise.all([workerCtx.rebuild(), manifestCtx.rebuild()]);
  await Promise.all([workerCtx.dispose(), manifestCtx.dispose()]);
}
