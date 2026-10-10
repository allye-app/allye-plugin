import { lstatSync } from "node:fs"
import { homedir } from "node:os"
import { isAbsolute, join } from "node:path"

type StatLike = { isDirectory(): boolean; isSymbolicLink(): boolean; uid: number; mode: number }

export type SkillsPathsOptions = {
  env?: Record<string, string | undefined>
  home?: string
  /** Current user id; null means unavailable (e.g. Windows), which rejects the org dir. */
  uid?: number | null
  lstat?: (path: string) => StatLike
}

/**
 * `${XDG_CONFIG_HOME:-~/.config}/opencode/allye-skills`, the same rule as the installer.
 * XDG_CONFIG_HOME is used only when non-empty and absolute; empty or relative falls
 * back to <home>/.config (XDG Base Directory spec). Trailing slashes are stripped.
 * Home is $HOME, falling back to os.homedir().
 */
export function allyeSkillsDir(env: Record<string, string | undefined> = process.env, home: string = env.HOME || homedir()): string {
  const xdg = env.XDG_CONFIG_HOME
  let base = xdg && isAbsolute(xdg) ? xdg : join(home, ".config")
  while (base.length > 1 && base.endsWith("/")) base = base.slice(0, -1)
  return join(base, "opencode", "allye-skills")
}

/** Existing config paths plus the extra ones not already present (no duplicates, order kept). */
export function mergeSkillsPaths(existing: readonly string[] | undefined, extra: readonly string[]): string[] {
  const merged = [...(existing ?? [])]
  for (const path of extra) if (!merged.includes(path)) merged.push(path)
  return merged
}

/** Bundled skills dir always; the org skills dir only when it is a real directory (not a symlink), owned by the current user and not group- or world-writable. */
export function skillsPaths(bundled: string, options: SkillsPathsOptions = {}): string[] {
  const env = options.env ?? process.env
  const uid = options.uid === undefined ? (process.getuid?.() ?? null) : options.uid
  const lstat = options.lstat ?? ((path: string) => lstatSync(path))
  const dir = allyeSkillsDir(env, options.home)
  try {
    const stat = lstat(dir)
    if (uid !== null && stat.isDirectory() && !stat.isSymbolicLink() && stat.uid === uid && (stat.mode & 0o022) === 0) return [bundled, dir]
  } catch {
    // missing or unreadable: bundled only
  }
  return [bundled]
}
