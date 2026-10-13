# Your organization's skills: details

Details of `install.sh`, the installer for the skills your organization keeps in Allye's **Skills** section. Usage and the overview are in the [README](../README.md#your-organizations-skills).

## Who can install

Any member with view access to a skill can install it: any tenant member for an organization skill, members of the skill's team for a team skill, the author for a personal skill. Each person's installs are recorded separately. The installer needs no team for the install itself; use `--team <id>` (or `ALLYE_TEAM_ID`) only when a skill slug matches skills in several teams, so the slug can be resolved (or pass the skill id instead). If view access is lost while an install is in progress, the API answers `409`, the installer rolls the swap back and tells you to get access and rerun.

## Where skills go

| Runtime | Skills directory |
|---|---|
| `claude` | `~/.claude/skills` |
| `codex` | `$CODEX_HOME/skills` when `CODEX_HOME` is set, otherwise `~/.codex/skills` |
| `opencode` | `${XDG_CONFIG_HOME:-~/.config}/opencode/allye-skills` |
| `pi` | `$PI_CODING_AGENT_DIR/skills` when set, otherwise `~/.pi/agent/skills` |
| `omp` | `~/.omp/agent/skills` |

`CODEX_HOME` and `PI_CODING_AGENT_DIR` must be absolute paths; only the empty string means unset, a trailing `/` is stripped (`/` itself stays `/`), and a relative value stops that runtime's install before any request (other runtimes are unaffected). An empty or relative `XDG_CONFIG_HOME` is treated as unset. OpenCode does not discover this directory by itself: the `allye-opencode` plugin adds it to `skills.paths` when it is a real directory (not a symlink) owned by you and not group- or world-writable, so restart OpenCode after the first install creates it. The installer refuses to install into an `allye-skills` directory that is a symlink or group/world-writable (fix with `chmod go-w <dir>`); it does not check ownership, so the plugin additionally ignores a directory that is not owned by you. OMP presents itself to the API as runtime `pi`; Pi and OMP skills are installed as plain directories, with no package receipt.

Changing `CODEX_HOME` or `PI_CODING_AGENT_DIR` changes the install target, and the installer does not migrate skills left in the old directory (for example `~/.codex/skills`). Those copies stay where they are; a copy found under the new directory is handled as in the next section.

## Edited, deleted and moved copies

| State of `<skills dir>/<name>` | What the installer does |
|---|---|
| Missing (first install or deleted) | Installs it again; the API records a reinstall when it already had an install for this machine |
| Unchanged copy of the same release | Reports "already installed"; nothing is sent |
| Unchanged copy of an older release | Updates it |
| Edited by you | Refuses and changes nothing; rerun with `--reinstall` |
| Not installed by the installer, or installed from another skill | Never touched, with or without `--reinstall` |
| Contains a symlink or special file | Refuses and names the entry; with or without `--reinstall` |

`--reinstall` replaces an edited copy with the approved release and keeps your edited folder at `~/.allye/backups/<adapter-id>/<name>.allye.backup.<UTC ts>` (`.<pid>` is appended if that name exists), outside every skills directory so no harness loads it. Backup directories are created with mode 0700, and the installer refuses to keep backups in a `~/.allye`, `backups` or `backups/<id>` that is a symlink, owned by someone else or group/world-writable (it changes nothing; fix the directory and rerun). The installer prints the path; backups are never overwritten or deleted, and `./install.sh status` does not list them. If anything fails before the install is recorded, your edited folder is put back.

A copy records the machine and skills path it was installed for (as a digest; the hostname and path never leave the machine). After a hostname change, a different home or a changed `CODEX_HOME`, `PI_CODING_AGENT_DIR` or `XDG_CONFIG_HOME`, existing copies are "other-target": an unchanged one is reinstalled automatically here with no backup, while an edited one needs `--reinstall`.

If an earlier run could not finish moving your edited folder (a failed restore, a failed backup move, or a killed run), it leaves `<skills dir>/.allye-backup.<name>.<UTC ts>.<pid>`. The installer then refuses to install `<name>`, prints each such path and sends nothing. Move the folder into `~/.allye/backups/<adapter-id>/` to keep it, or delete it, then rerun.

## Errors

- `409 DISTRIBUTION_NOT_AUTHORIZED`: you need view access to the skill (team membership or authorship); get access and rerun.
- `410 MARKETPLACE_RETIRED`: the skill is a retired, read-only marketplace skill; nothing was installed. Use an organization or team skill.
- `422 TEAM_SELECTION_REQUIRED`: the slug matches skills in several teams; rerun with `--team <team>` or use the skill id.
- `409 RUNTIME_INCOMPATIBLE`: the API has no `1.1.0` profile, which is the case on PROD before the allye-api release. Use HML or wait for that release; there is nothing to reset and no admin to ask.
- `400` mentioning a request field such as `idempotencyKey` or `target`: the API and the installer disagree on the request shape. Upgrade the installer; there is nothing to reset and no admin to ask.
