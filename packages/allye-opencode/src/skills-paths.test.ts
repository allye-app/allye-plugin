import { test } from "node:test"
import assert from "node:assert/strict"
import { mkdtempSync, mkdirSync, symlinkSync, writeFileSync, rmSync, chmodSync } from "node:fs"
import { tmpdir, homedir } from "node:os"
import { join } from "node:path"
import { allyeSkillsDir, mergeSkillsPaths, skillsPaths } from "./skills-paths.ts"

const BUNDLED = "/bundled/skills"
const uid = process.getuid!()

function fixture() {
  const root = mkdtempSync(join(tmpdir(), "allye-skills-paths-"))
  const xdg = join(root, "xdg")
  mkdirSync(join(xdg, "opencode"), { recursive: true })
  return { root, xdg, dir: join(xdg, "opencode", "allye-skills"), done: () => rmSync(root, { recursive: true, force: true }) }
}

test("XDG_CONFIG_HOME set: dir is $XDG/opencode/allye-skills", () => {
  assert.equal(allyeSkillsDir({ XDG_CONFIG_HOME: "/x/cfg" }, "/home/u"), "/x/cfg/opencode/allye-skills")
})

test("XDG_CONFIG_HOME unset or empty: falls back to ~/.config", () => {
  assert.equal(allyeSkillsDir({}, "/home/u"), "/home/u/.config/opencode/allye-skills")
  assert.equal(allyeSkillsDir({ XDG_CONFIG_HOME: "" }, "/home/u"), "/home/u/.config/opencode/allye-skills")
})

test("relative XDG_CONFIG_HOME is ignored: falls back to ~/.config", () => {
  assert.equal(allyeSkillsDir({ XDG_CONFIG_HOME: "rel" }, "/home/u"), "/home/u/.config/opencode/allye-skills")
})

test("trailing slashes are stripped; root stays root", () => {
  assert.equal(allyeSkillsDir({ XDG_CONFIG_HOME: "/x/cfg//" }, "/home/u"), "/x/cfg/opencode/allye-skills")
  assert.equal(allyeSkillsDir({ XDG_CONFIG_HOME: "/" }, "/home/u"), "/opencode/allye-skills")
})

test("HOME unset: falls back to os.homedir()", () => {
  assert.equal(allyeSkillsDir({}), join(homedir(), ".config", "opencode", "allye-skills"))
})

test("~/.config fallback finds a real dir under a fixture HOME", () => {
  const f = fixture()
  try {
    const dir = join(f.root, "home", ".config", "opencode", "allye-skills")
    mkdirSync(dir, { recursive: true })
    assert.deepEqual(skillsPaths(BUNDLED, { env: { HOME: join(f.root, "home") } }), [BUNDLED, dir])
    assert.deepEqual(skillsPaths(BUNDLED, { env: { HOME: join(f.root, "home"), XDG_CONFIG_HOME: "rel" } }), [BUNDLED, dir])
  } finally {
    f.done()
  }
})

test("group- or world-writable directory is rejected; 0755 and 0700 are accepted", () => {
  const f = fixture()
  try {
    mkdirSync(f.dir)
    const env = { XDG_CONFIG_HOME: f.xdg }
    for (const [mode, ok] of [[0o755, true], [0o700, true], [0o775, false], [0o770, false], [0o777, false]] as const) {
      chmodSync(f.dir, mode)
      assert.deepEqual(skillsPaths(BUNDLED, { env }), ok ? [BUNDLED, f.dir] : [BUNDLED], mode.toString(8))
    }
  } finally {
    f.done()
  }
})

test("mergeSkillsPaths: undefined, already present, absent org dir", () => {
  assert.deepEqual(mergeSkillsPaths(undefined, [BUNDLED, "/o"]), [BUNDLED, "/o"])
  assert.deepEqual(mergeSkillsPaths([BUNDLED, "/u"], [BUNDLED, "/o"]), [BUNDLED, "/u", "/o"])
  assert.deepEqual(mergeSkillsPaths(["/o", BUNDLED], [BUNDLED, "/o"]), ["/o", BUNDLED])
  assert.deepEqual(mergeSkillsPaths(["/u"], [BUNDLED]), ["/u", BUNDLED])
})

test("real directory owned by the current user is appended after the bundled dir", () => {
  const f = fixture()
  try {
    mkdirSync(f.dir)
    assert.deepEqual(skillsPaths(BUNDLED, { env: { XDG_CONFIG_HOME: f.xdg } }), [BUNDLED, f.dir])
  } finally {
    f.done()
  }
})

test("missing directory: only the bundled dir", () => {
  const f = fixture()
  try {
    assert.deepEqual(skillsPaths(BUNDLED, { env: { XDG_CONFIG_HOME: f.xdg } }), [BUNDLED])
  } finally {
    f.done()
  }
})

test("symlink to a directory is rejected", () => {
  const f = fixture()
  try {
    mkdirSync(join(f.root, "target"))
    symlinkSync(join(f.root, "target"), f.dir)
    assert.deepEqual(skillsPaths(BUNDLED, { env: { XDG_CONFIG_HOME: f.xdg } }), [BUNDLED])
  } finally {
    f.done()
  }
})

test("regular file is rejected", () => {
  const f = fixture()
  try {
    writeFileSync(f.dir, "x")
    assert.deepEqual(skillsPaths(BUNDLED, { env: { XDG_CONFIG_HOME: f.xdg } }), [BUNDLED])
  } finally {
    f.done()
  }
})

test("real directory owned by another uid is rejected (injected uid)", () => {
  const f = fixture()
  try {
    mkdirSync(f.dir)
    assert.deepEqual(skillsPaths(BUNDLED, { env: { XDG_CONFIG_HOME: f.xdg }, uid: uid + 1 }), [BUNDLED])
    assert.deepEqual(skillsPaths(BUNDLED, { env: { XDG_CONFIG_HOME: f.xdg }, uid }), [BUNDLED, f.dir])
  } finally {
    f.done()
  }
})

test("injected lstat decides: other owner rejected, own accepted", () => {
  const own = { isDirectory: () => true, isSymbolicLink: () => false, uid: 1000, mode: 0o755 }
  const env = { XDG_CONFIG_HOME: "/x" }
  const dir = "/x/opencode/allye-skills"
  assert.deepEqual(skillsPaths(BUNDLED, { env, uid: 1000, lstat: () => own }), [BUNDLED, dir])
  assert.deepEqual(skillsPaths(BUNDLED, { env, uid: 1000, lstat: () => ({ ...own, uid: 0 }) }), [BUNDLED])
  assert.deepEqual(skillsPaths(BUNDLED, { env, uid: 1000, lstat: () => { throw new Error("ENOENT") } }), [BUNDLED])
})

test("uid unavailable (no getuid): only the bundled dir", () => {
  const own = { isDirectory: () => true, isSymbolicLink: () => false, uid: 1000, mode: 0o755 }
  assert.deepEqual(skillsPaths(BUNDLED, { env: { XDG_CONFIG_HOME: "/x" }, uid: null, lstat: () => own }), [BUNDLED])
})
