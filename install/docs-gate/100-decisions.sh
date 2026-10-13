#!/bin/bash
# ALY-46.10: Decisions pages and the Changelog entry on spec completion (BR-04, AC-12, D-94):
# proposed in the docs summary, created only after the user's confirmation, deduped on rerun
# with kb_tree by spec key + anchor, memory holding only a hint. Asserts exact lines so an
# inverted or qualified rule fails, plus a deny-list for added contradictions.
# Runnable alone; exits 0 or 1.
set -euo pipefail
# shellcheck source=install/docs-gate/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
S="skills/bridge/SKILL.md"
P="skills/bridge-navigator/SKILL.md"

# each_once <file>: every non-empty line on stdin appears in <file> exactly once.
each_once() { while IFS= read -r l; do [ -z "$l" ] || count_line "$1" "$l" 1; done; }

# next_line <file> <exact line>: the next non-empty line after it.
next_line() { awk -v w="$2" 'f && NF {print; exit} $0 == w {f=1}' "$ROOT/$1"; }

# Mothership: four consecutive Approvals bullets right after the Docs bullet.
SK_DOCS='- Docs: on a mission with a docs task, the push/PR proposal also shows the docs summary, and the user'"'"'s yes covers publishing exactly the listed staged pages to `kb`, only after `SHIELD_CLEAR` and `WATCHER_APPROVED` for the reviewed point; a refusal publishes nothing, and a conflict or changed revision stops publishing and returns to re-stage and re-approve (`publish.md` §7).'
B1='- Decisions: when the mission'"'"'s spec has `adr: yes` decisions, the docs summary (`publish.md` §7) also proposes one Decisions page per such decision, with the sections context, decision, consequences and the source spec key, titled with the spec key prefix (`<spec key> [D-NN] <decision title>`, e.g. `ALY-46 [D-94] <decision title>`) under the project'"'"'s Decisions folder, and one Changelog entry for the spec. They are created only after the user'"'"'s confirmation, by the same yes as the docs summary, listed page by page; the Navigator stages and publishes them in the docs task.'
B2='- Decisions rerun: before proposing, list the Decisions folder with `kb_tree` and skip every decision whose page title already starts with the same spec key and anchor (`<spec key> [D-NN]`); the Changelog entry dedupes the same way, skipped when the Changelog page (read by short_id) already has the section for that spec key. `kb_search` never decides a dedupe: its index lags.'
B3='- Decisions folder: a missing Decisions or Changelog folder is proposed for creation under the project tree (survey'"'"'s standard tree) in the same confirmation; it is never created under any other parent.'
B4='- Decisions memory: memory holds at most a short hint pointing to the Decisions page (`kb-page:<short_id>`); the decision text stays on the page.'
B5='- Decisions and Docs impact: a spec with `adr: yes` decisions whose Docs impact is `none` is inconsistent; before planning, ask the user to add the `decision` impact and the final docs task (a scope change, `workflow.md` §10). Without that, no Decisions page is proposed, and the final output reports the gap.'
B6='- Decisions prefix match: on a title-prefix match, read that page by short_id and check its source spec key section; a mismatch is reported to the user, never silently skipped.'
for l in "$B1" "$B2" "$B3" "$B4" "$B5" "$B6"; do count_line "$S" "$l" 1; done
[ "$(next_line "$S" "$SK_DOCS")" = "$B1" ] || fail "$S: the Decisions bullet must follow the Docs bullet directly"
[ "$(next_line "$S" "$B1")" = "$B2" ] || fail "$S: Decisions rerun must follow Decisions directly"
[ "$(next_line "$S" "$B2")" = "$B3" ] || fail "$S: Decisions folder must follow Decisions rerun directly"
[ "$(next_line "$S" "$B3")" = "$B4" ] || fail "$S: Decisions memory must follow Decisions folder directly"
[ "$(next_line "$S" "$B4")" = "$B5" ] || fail "$S: Decisions and Docs impact must follow Decisions memory directly"
[ "$(next_line "$S" "$B5")" = "$B6" ] || fail "$S: Decisions prefix match must follow Decisions and Docs impact directly"
case "$(awk '/^## Approvals$/ {on=1; next} on && /^## / {exit} on' "$ROOT/$S")" in
  *"$B6"*) ;; *) fail "$S: the Decisions bullets must sit inside ## Approvals" ;;
esac

# Navigator (D-102): the Stage and Publish bullets of the Docs task; SHD-33 folder and Changelog creates.
P1='- Decisions and Changelog (only as the packet lists them, from the Mothership'"'"'s deduped proposal): stage each Decisions page as `new-<Decisions short_id>-<kebab title>.md` (sections context, decision, consequences and the source spec key; title `<spec key> [D-NN] <decision title>`) and the Changelog entry as `<Changelog short_id>.md`, the current Changelog page with the spec'"'"'s section appended.'
P2='- Decisions and Changelog, in the publish phase only and under the same rules (the user'"'"'s approval, `mission_ref`, the `contentSha256` recheck): create each approved Decisions page with `kb_create` naming the Decisions folder as `parent`, and append the Changelog entry with `kb_section` (mode append, `base_revision`).'
P3='- A missing Decisions folder (only as the packet lists it): stage it as `new-<project root short_id>-decisions.md`; its Decisions pages stage as `new-new-decisions-<kebab title>.md`.'
P3B='- A missing Changelog page (only as the packet lists it): stage it as `new-<project root short_id>-changelog.md`, a whole new page whose first section is the spec'"'"'s entry.'
P4='- The staged file of an existing Changelog page equals the base page plus exactly one appended section, the spec'"'"'s entry.'
P5='- Publish a staged folder first in the approved list; its returned id becomes the `parent` of every `new-new-<folder kebab>-` page staged under it.'
P7='- A missing Changelog page is created whole with `kb_create`, naming the project root as `parent`.'
P6='- Changelog: append exactly its one staged section with `kb_section`; any other difference between the staged file and the base page stops publishing and returns to re-stage, and the Changelog is never written with `kb_update`.'
each_once "$P" <<EOF
$P1
$P2
$P3
$P3B
$P4
$P5
$P6
$P7
EOF
[ "$(next_line "$P" "$P1")" = "$P3" ] || fail "$P: the missing-folder stage bullet must follow the Decisions stage bullet"
[ "$(next_line "$P" "$P3")" = "$P3B" ] || fail "$P: the missing-Changelog stage bullet must follow the missing-folder bullet"
[ "$(next_line "$P" "$P3B")" = "$P4" ] || fail "$P: the Changelog stage bullet must follow the missing-Changelog bullet"
[ "$(next_line "$P" "$P2")" = "$P5" ] || fail "$P: the folder-first bullet must follow the Decisions publish bullet"
[ "$(next_line "$P" "$P5")" = "$P6" ] || fail "$P: the Changelog publish bullet must follow the folder-first bullet"
[ "$(next_line "$P" "$P6")" = "$P7" ] || fail "$P: the missing-Changelog create must follow the Changelog publish bullet"
stage=$(awk '/^\*\*Stage\*\*/ {on=1; next} on && /^\*\*Publish\*\*/ {exit} on' "$ROOT/$P")
publish=$(awk '/^\*\*Publish\*\*/ {on=1; next} on && /^\*\*Personal notes\*\*/ {exit} on' "$ROOT/$P")
case "$stage" in *"$P1"*) ;; *) fail "$P: the Decisions stage bullet must sit under **Stage**" ;; esac
case "$publish" in *"$P2"*) ;; *) fail "$P: the Decisions publish bullet must sit under **Publish**" ;; esac

# Deny-list: inversions and weakenings (case-insensitive).
for f in "$S" "$P"; do
  deny "$f" '(decisions|changelog)[^.;]*(created|appended|published|written)[^.;]*before'
  deny "$f" '(decisions|changelog)[^.;]*without[^.;]*(confirm|yes|approval)'
  deny "$f" '(dedupe|deduplicat|skip)[^.;]*`kb_search`|`kb_search`[^.;]*(to|for) (dedupe|deduplicat|match)'
  deny "$f" 'memory[^.;]*(decision text|context, decision|consequences)'
  deny "$f" 'changelog[^.;]*(without|no) (a )?(dedupe|check)|(always|each rerun)[^.;]*(append|add)[^.;]*changelog'
  deny "$f" '(may|can) (use|pick|choose|invent)[^.;]*(other|another|new) parent'
  deny "$f" 'source spec key[^.;]*(optional|may be omitted)'
  deny "$f" 'adr: yes[^.]*(is|are) consistent|(propose|create)[^.;]*decisions pages?[^.;]*without (the|a) docs task'
  deny "$f" 'mismatch[^.;]*(is|are) (silently )?skipped|mismatch[^.;]*skip (it|the)'
  deny "$f" '(use|with|through|call) `kb_update`[^.;]*changelog|changelog[^.;]*(may|can) (use|be written with) `kb_update`'
  deny "$f" 'changelog[^.;]*(more than one|several|any number of) (appended )?sections?'
  deny "$f" 'folder[^.;]*(published|created) (last|after the pages)'
done
deny "$S" '(save|store|keep|write)[^.]*decision text[^.]*memory|memory[^.]*(stores?|holds?|keeps?) the decision text'

finish
