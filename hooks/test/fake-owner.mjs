// Fake owning Claude Code process for hooks/test-live-report.sh (ALY-217 D-21). Run by node here only, by absolute
// path from the harness; never on the hook PATH.
//
// Usage: <node or a symlink to node> fake-owner.mjs OUTDIR COMMAND [ARGS...]
// The launcher re-spawns itself detached (new session, so its own process group: a SIGHUP sent to that group never
// reaches the harness) through the same executable path it was started with (argv0, so a symlink named `tmux`
// gives an owner whose comm is `tmux`), then exits. The detached copy is the owner: it writes OUTDIR/owner as
// "<pid> <pgid>", ignores SIGHUP, runs COMMAND ARGS with stdio on /dev/null (same process group), writes OUTDIR/rc
// when it exits and stays alive until the harness kills it by its recorded pid.
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, renameSync } from "node:fs";
import { basename, isAbsolute } from "node:path";
import { fileURLToPath } from "node:url";

const self = fileURLToPath(import.meta.url);
const exe = isAbsolute(process.argv0) ? process.argv0 : process.execPath;

function writeAtomic(path, text) {
  writeFileSync(`${path}.tmp`, text);
  renameSync(`${path}.tmp`, path);
}

if (process.argv[2] !== "--owner") {
  const child = spawn(exe, [self, "--owner", ...process.argv.slice(2)], { detached: true, stdio: "ignore" });
  child.unref();
  process.exit(0);
}

const [, , , outdir, cmd, ...args] = process.argv;
// Recent node names its main thread `node-MainThread`; the title sets the comm back to the executable's name.
process.title = basename(process.argv0);
process.on("SIGHUP", () => {});
const stat = readFileSync("/proc/self/stat", "utf8");
const pgid = stat.slice(stat.lastIndexOf(")") + 2).split(" ")[2];
writeAtomic(`${outdir}/owner`, `${process.pid} ${pgid}`);
const run = spawn(cmd, args, { stdio: "ignore" });
run.on("exit", (code, signal) => writeAtomic(`${outdir}/rc`, String(code ?? signal)));
run.on("error", () => writeAtomic(`${outdir}/rc`, "spawn-error"));
setInterval(() => {}, 1 << 30);
