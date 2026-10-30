#!/bin/bash
# Claude Code blocking PermissionRequest hook of the Live return channel (ALY-269, D-07). Slice ALY-269.3: the answer CLIENT.
# It opens a request on the Allye API and waits for the answer; in this slice it never prints a decision (questions, permissions
# phrases, risk and the output stage come with ALY-269.4 and .5). stdin = the Claude Code hook JSON, stdout = hook output.
#
# Contract (BR-02, AC-16): the terminal keeps the last word. On any doubt the script exits 0 with no output; every exit below is
# a literal `exit 0`, there is no `set -e`, and a top-level ERR trap ends with exit 0. stderr is never written (`exec 2>/dev/null`),
# nothing is sent to stdout in this slice. Runtime: bash 3.2+, curl, jq, sha256sum or shasum.
#
# Origin and credential (AC-17, D-15, D-16): the API origin and the token come ONLY from the pairing file, read through
# hooks/lib/credential.sh (load_live_credential); no environment variable or project setting is consulted for either. The origin is
# https, or loopback http for development (valid_api_url): curl gets `--proto '=https'` for an https origin and `--proto '=http'`
# only when the paired origin is the loopback http one. `--max-redirs 0`, never `-L`. The credential goes to curl on stdin as a `-K -`
# config (never argv). curl's stdin is taken by that config, so the request body travels as the config line `data-binary = "@FILE"`
# of a 0600 file in a private mktemp directory under $CLAUDE_PLUGIN_DATA/live (the same mechanism as hooks/live-report.sh); the
# directory is removed by the EXIT trap. curl runs as `env -u ... curl`: the TLS-related variables a project setting could inject
# (CURL_CA_BUNDLE, SSL_CERT_FILE, SSL_CERT_DIR, SSLKEYLOGFILE, CURL_HOME, CURL_SSL_BACKEND) are unset for it; env execs curl, so $! is curl's pid. Nothing secret or textual is ever on a command line.
#
# Hash (AC-05, D-08): sha256 hex of `jq -S -c` over the array [tool_name, tool_input] (for tool_name AskUserQuestion, over
# .tool_input.questions alone), streamed through stdin. The bytes are jq's output INCLUDING its trailing newline, exactly as
# hooks/live-report.sh slice .2 computes `h`. The session is identified to the API by session_hash = sha256 of the session_id (no
# trailing newline), the same value as the reporter's HASH.
#
# Open (AC-06): POST /api/live/requests {session_hash, kind, hash, risk, tool} (no tu, never; `after` is slice .10), --max-time 2.
# answerable false: exit at once. true: poll GET /api/live/requests/:id/wait until the deadline = min(110 s, expiresAt), each chunk
# --max-time min(30, remaining - 1), stopping when 1 s or less remains. 110 is the default of ANSWER_BUDGET_DEFAULT below;
# LIVE_ANSWER_BUDGET_S (digits, at most 110) lowers it and exists for tests only. Every status ends the loop here except `pending`.
#
# Backoff (AC-12): after an open failure the file $CLAUDE_PLUGIN_DATA/live/answer-backoff holds `<until epoch> <sha256 of the token>`
# (written like the reporter's `backoff` and `notu` files: private file, mktemp + mv): 60 s after a connect failure, timeout, 5xx or
# any other failure, 10 minutes after a 404 without the code run_not_found, or a 405, none after 429 and none after a 404 run_not_found
# (deliberate refinement of AC-12: the run may not exist yet at the first tool call; the next request opens again).
# While it lasts the script exits at once with no network call. It is a per-credential file, not a key of the per-session state
# file (that file holds one validated state word); the same precedent as `notu` of slice ALY-269.2.
#
# Questions (ALY-269.4, AC-03, AC-08, AC-09, AC-18, AC-19, BR-01, BR-03): for tool_name AskUserQuestion (and only then) the open is
# {session_hash, kind: question, hash, risk: normal, tool: AskUserQuestion, questions}. `questions` keeps ONLY header, question,
# multiSelect (boolean) and option label and description of at most 4 questions and 4 options each, every text cleaned and capped by
# the reporter's cleaner (QCLEAN_DEFS below, copied verbatim from hooks/live-report.sh `actbad` .. `actclean`, ALY-217.6/263.6/263.9;
# caps header 40, question 400, label 100, description 300; minimum one word). A required text the cleaner removes entirely, a question
# without options or a non-object entry means no open (the API is strict; a 400 would be a backoff). Detailed Live off (the reporter's
# activity-off or detailed-off entry in the live directory, any entry counts) means no open and no network call at all. The ORIGINAL
# tool_input is kept in the 0600 file $T/orig (never on argv) and removed with $T by the EXIT trap.
# Output (AC-08): only on `answered` with a decision {answers: [{q, picks, other?}]} that passes a STRICT check, and then ONE printf of
#   {"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedInput":<tool_input + answers>}}}
# where `answers` is keyed by the ORIGINAL question text and holds the ORIGINAL option labels picked by INDEX (sorted by index, joined
# with "," and no space; `other` alone, or after the labels, joined with ","). Valid = an object with only `answers`; one entry per
# question (q an integer in range, no duplicate q); picks distinct integers in range of the option list; a single-choice question has
# exactly one pick and no `other`, or no pick and an `other`; a multiSelect question has at least one pick or an `other`; `other`
# a string that is not empty after sanitising (AC-19: control, bidi, zero-width, tag and other format characters removed, at most 500
# characters, NFC through `uconv -x any-nfc` when that tool is on the PATH; without it the strip and cap are applied and the decomposed
# form is kept, and a failing uconv prints nothing). Question texts must be unique strings (they are the answer keys). Anything else,
# `behavior` or any permission style decision included, prints nothing: the terminal keeps the last word. The request is already
# answered on the server then, so there is no cancel; no ack either (nothing was delivered). After a successful print: ack (--max-time 2,
# result ignored). The jq output is ASCII only (-a), a single line.
# Stale files (SHD-03): at start `.answer.*` directories and `.answer-backoff.*` files of the user older than 10 minutes (no
# symlinks) are removed from the live directory, best effort and silent (find -mmin; GNU and BSD find both have it).
#
# Cleanup (AC-14): the EXIT trap (also run by INT, TERM and HUP) kills the child it started, sends a best-effort
# POST /api/live/requests/:id/cancel (--max-time 1) while the request is still pending (opened; no answered, terminal, expired or
# API error seen), and removes its temp directory. Debug: LIVE_ANSWER_DEBUG=1 writes fixed stage words to a 0600 file
# $CLAUDE_PLUGIN_DATA/live/answer-debug.log, never to stderr, never a credential, nonce, text or decision body.
trap 'exit 0' ERR
umask 077
LC_ALL=C
exec 2>/dev/null
trap '' PIPE

ANSWER_BUDGET_DEFAULT=110
BUDGET="$ANSWER_BUDGET_DEFAULT"
case "${LIVE_ANSWER_BUDGET_S:-}" in
  ''|*[!0-9]*) ;;
  *) if [ "${#LIVE_ANSWER_BUDGET_S}" -le 3 ] && [ "$((10#$LIVE_ANSWER_BUDGET_S))" -ge 1 ] && [ "$((10#$LIVE_ANSWER_BUDGET_S))" -lt "$ANSWER_BUDGET_DEFAULT" ]; then BUDGET=$((10#$LIVE_ANSWER_BUDGET_S)); fi ;;
esac

T=""; CPID=""; SPID=""; RID=""; PENDING=0; API=""; DBGF=""; CFP=""; HC=""; CRC=0
LIVE_TOKEN=""; LIVE_API=""

private_file_ok() {  # absent, or a regular file (no symlink) of the user with mode 0600
  { [ ! -e "$1" ] && [ ! -L "$1" ]; } && return 0
  [ -n "$(find "$1" -prune -type f -user "$UID_NOW" -perm 0600 -print 2>/dev/null)" ]
}

dbg() {  # a fixed stage word and numbers only
  [ "${LIVE_ANSWER_DEBUG:-}" = 1 ] || return 0
  [ -n "$DBGF" ] || return 0
  [ ! -L "$DBGF" ] && private_file_ok "$DBGF" || return 0
  printf '%s\n' "$1" >>"$DBGF" 2>/dev/null || true
  return 0
}

now_epoch() {  # sets NOW
  NOW="${EPOCHSECONDS:-}"
  [[ "$NOW" =~ ^[0-9]{1,12}$ ]] || NOW=$(date +%s 2>/dev/null) || NOW=""
  [[ "$NOW" =~ ^[0-9]{1,12}$ ]]
}

# api_call METHOD PATH MAXTIME WITH_BODY: runs curl in the background and waits for it (so a signal is handled at once). Sets HC
# (the HTTP status or empty) and CRC (curl's exit status). The response body is in $T/resp.
api_call() {
  local m="$1" p="$2" mt="$3" wb="$4"
  HC=""; CRC=0
  : >"$T/code" 2>/dev/null || { CRC=1; return 0; }
  rm -f "$T/resp" 2>/dev/null || true
  {
    printf 'url = "%s%s"\n' "$API" "$p"
    printf 'request = "%s"\n' "$m"
    printf 'header = "Authorization: Bearer %s"\n' "$LIVE_TOKEN"
    printf 'header = "Content-Type: application/json"\n'
    printf 'header = "Accept: application/json"\n'
    [ "$wb" = 1 ] && printf 'data-binary = "@%s"\n'  "$T/body"
    printf 'max-time = %s\nconnect-timeout = %s\nnoproxy = "*"\n' "$mt" "$mt"
  } | env -u CURL_CA_BUNDLE -u SSL_CERT_FILE -u SSL_CERT_DIR -u SSLKEYLOGFILE -u CURL_HOME -u CURL_SSL_BACKEND curl -q --silent "${PROTO[@]}" --max-redirs 0 --max-filesize 65536 -K - -o "$T/resp" -w '%{http_code}' >"$T/code" 2>/dev/null &
  CPID=$!
  wait "$CPID" && CRC=0 || CRC=$?
  CPID=""
  { IFS= read -r HC <"$T/code"; } 2>/dev/null || true   # no trailing newline: read returns 1 with the value set
  [[ "$HC" =~ ^[0-9]{3}$ ]] || HC=""
  return 0
}

backoff_active() {
  local u="" f=""
  [ -f "$BACKOFFF" ] && [ ! -L "$BACKOFFF" ] && private_file_ok "$BACKOFFF" || return 1
  { IFS=' ' read -r u f <"$BACKOFFF"; } 2>/dev/null || true
  [[ "$u" =~ ^[0-9]{1,12}$ ]] && [ "$f" = "$CFP" ] || return 1
  now_epoch || return 1
  [ "$NOW" -lt "$u" ]
}
backoff_set() {  # SECONDS from now, for this credential; best effort
  local tmp
  now_epoch || return 0
  tmp=$(mktemp "$LIVE_DIR/.answer-backoff.XXXXXX" 2>/dev/null) || return 0
  printf '%s %s' "$((NOW + $1))" "$CFP" >"$tmp" 2>/dev/null && mv -f "$tmp" "$BACKOFFF" 2>/dev/null || rm -f "$tmp" 2>/dev/null || true
  return 0
}

cleanup() {
  trap '' INT TERM HUP
  if [ -n "$CPID" ] && kill -0 "$CPID" 2>/dev/null; then kill "$CPID" 2>/dev/null || true; wait "$CPID" 2>/dev/null || true; fi
  if [ -n "$SPID" ] && kill -0 "$SPID" 2>/dev/null; then kill "$SPID" 2>/dev/null || true; wait "$SPID" 2>/dev/null || true; fi
  CPID=""; SPID=""
  if [ "$PENDING" = 1 ] && [ -n "$RID" ] && [ -n "$T" ] && [ -d "$T" ]; then
    PENDING=0
    api_call POST "/api/live/requests/$RID/cancel" 1 0
    dbg "cancel sent"
  fi
  if [ -n "$T" ]; then rm -rf "$T" 2>/dev/null || true; fi
  return 0
}

# hash_of SELECTOR: sha256 hex of the canonical JSON read from stdin. SELECTOR permission: [tool_name, tool_input]; question: the
# questions array alone (wired in slice .4; the selector exists now).
hash_of() {
  case "$1" in
    question)   # the reporter's guarded filter: no hash when questions is absent or not an array
      local q; q=$(jq -S -c '.tool_input | objects | .questions | arrays // empty') || return 1
      [ -n "$q" ] || return 1
      printf '%s\n' "$q" | sha_hex ;;
    *) jq -S -c '[.tool_name, .tool_input]' | sha_hex ;;
  esac
}

QCLEAN_DEFS=$(cat <<'QEOF'
def actbad: . < 32 or (. >= 127 and . <= 159) or . == 173 or . == 847 or (. >= 1536 and . <= 1541) or . == 1564 or . == 1757
  or . == 1807 or . == 2192 or . == 2193 or . == 2274 or . == 6158 or (. >= 8203 and . <= 8207) or (. >= 8234 and . <= 8238)
  or (. >= 8288 and . <= 8303) or (. >= 55296 and . <= 57343) or (. >= 65024 and . <= 65039) or . == 65279
  or (. >= 65529 and . <= 65533) or . == 69821 or . == 69837 or (. >= 78896 and . <= 78911) or (. >= 113824 and . <= 113827)
  or (. >= 119155 and . <= 119162) or (. >= 917504 and . <= 917631) or (. >= 917760 and . <= 917999);
def actws: . == 9 or . == 10 or . == 11 or . == 12 or . == 13 or . == 133 or . == 160 or . == 5760 or (. >= 8192 and . <= 8202)
  or . == 8232 or . == 8233 or . == 8239 or . == 8287 or . == 12288;
# D-23 step 4, one token: dropped as a path, URL, email, IP address, long base64/hex string or secret.
def actcore: gsub("\\A[\"\u0027(\\[{<,;.!?]+|[\"\u0027)\\]}>,;.!?]+\\z"; "");
def actpath: test("[/\\\\]") or (actcore | test("\\A(~|[A-Za-z]:)"));
# ALY-258 (SHD-01 of ALY-257): the API network rules. A token is split on = , ; [ ] ( ) | and every piece is tested whole, without
# leading/trailing `:` and without a `:port` suffix, as an e-mail, IPv4 (with port), IPv6, URL/www/arn:, hostname (also *.internal,
# *.local, *.corp) or a digit shape of 10+ digits. Mirrors pieceIsIdentifier of agent-run-text-scrub.ts.
def actbare: gsub("\\A[\"\u0027(\\[{<\u201c\u2018\u00ab]+"; "") | gsub("[\"\u0027)\\]}>\u201d\u2019\u00bb,;!?.]+\\z"; "");
def actident:
  length > 0 and (
    (contains("@") and contains("."))
    or test("\\A[0-9]{1,3}(\\.[0-9]{1,3}){3}(:[0-9]{1,5})?\\z")
    or (test("\\A[0-9A-Fa-f.:]{3,}\\z") and ([match(":"; "g")] | length) as $n | $n >= 2 and (contains("::") or $n == 7))
    or (ascii_downcase | (contains("://") or contains("www.") or startswith("arn:")))
    or (ascii_downcase | test("\\.(internal|local|corp)\\z") or test("\\A([a-z0-9-]+\\.)+[a-z]{2,24}\\z"))
    or (test("\\A[0-9()+./-]*\\z") and ([match("[0-9]"; "g")] | length) >= 10));
def actnet:
  [splits("[=,;\\[\\]()|]")] | any(
    actbare as $b | ($b | actident) or ($b | gsub("\\A:+|:+\\z"; "") | . as $t | actident or (sub(":[0-9]{1,5}\\z"; "") | . != $t and actident)));
# ALY-263.9: the secret-shaped drops shared by actdrop and the basename of the classifier (a file name is not a hostname: only these apply to it).
def namedrop:
  test("[0-9A-Fa-f]{16,}")
  or ([match("[A-Za-z0-9+/=_-]{20,}"; "g").string | select(test("[0-9]"))] | length > 0)
  or test("[A-Za-z0-9_-]{24,}")
  # D-20 subset (ALY-258): the distinctive secret prefixes anywhere in the token; sk-/sk_/pk-/rk- only at its start or
  # after a non-alphanumeric (so risk-based survives); arn:; hostnames; colon/dash separated hex pairs.
  or test("(ghp_|gho_|ghs_|github_pat_|xox[abprs]-|AKIA|ASIA|eyJ|glpat-)")
  or test("(\\A|[^A-Za-z0-9])(sk-|sk_|pk-|rk-)");
def actdrop:
  actcore as $c
  | test("[/\\\\]") or ($c | test("\\A(~|[A-Za-z]:)")) or contains("://") or ($c | ascii_downcase | startswith("www."))
    or test("[^@]@[^@]+\\.[^@]") or ($c | test("\\A[0-9]{1,3}(\\.[0-9]{1,3}){3}(:[0-9]{1,5})?\\z")) or contains("::")
    or ($c | test("\\A[0-9A-Fa-f]{0,4}(:[0-9A-Fa-f]{0,4}){2,}\\z"))
    or namedrop
    or ($c | ascii_downcase | startswith("arn:"))
    or ($c | test("\\A([A-Za-z0-9-]+\\.){2,}[A-Za-z]{2,}\\z"))
    or ($c | test("\\A([A-Za-z0-9-]+\\.)+(com|net|org|io|dev|app|co|br|ai|cloud|info|biz|edu|gov|local|internal|corp|test|lan)\\z"; "i"))
    or test("([0-9A-Fa-f]{2}[:-]){7}[0-9A-Fa-f]{2}")
    or actnet
    or test("[\uff00-\uffef]");   # fullwidth/halfwidth forms: look-alikes of ASCII that the API would NFKC-normalise (the plugin cannot) are dropped whole
# Secrets (D-23 step 4 and Shield SHD-01/03 of ALY-217.6). actkv: `key=value` / `key:value` (also bare `key:`, actbare);
# actkey: a key-like word alone; actsep: a standalone `=` / `:`; actscheme: an auth scheme; actauth: auth/authorization;
# actword: a secret word whose next token (after an optional is/as/=) is its value.
# actwk: the whole-word secret names of D-20 that are too common as substrings (session, sid...) to match inside a word.
def actwk: (. | ascii_downcase) | IN("pwd","pw","cookie","session","sid","passphrase","key","auth","bearer","credential","apikey");
def actkv: test("\\A[^=:]*(key|token|secret|pass|auth|credential)[^=:]*[=:]"; "i") or test("\\A(pwd|pw|cookie|session|sid)[=:]"; "i");
def actbare: test("\\A[^=:]*(key|token|secret|pass|auth|credential)[^=:]*[=:]+[\"\u0027]?\\z"; "i") or test("\\A(pwd|pw|cookie|session|sid)[=:]+[\"\u0027]?\\z"; "i");
def actkey: actcore | (test("(key|token|secret|pass|auth|credential)"; "i") or actwk);
def actsep: actcore | test("\\A[=:]+\\z");
def actscheme: (actcore | ascii_downcase) | IN("basic","bearer","token","digest");
def actauth: (actcore | ascii_downcase | sub("[=:]+\\z"; "")) | IN("auth","authorization","proxy-authorization");
def actword: (actcore | ascii_downcase) | IN("password","passwd","secret","token","apikey","api_key","access_key","private_key","credential","credentials");
def actbearer: (actcore | ascii_downcase) == "bearer";
# The cleaned phrase of a field, or null: (1) strings only; (2) whitespace to spaces, forbidden code points stripped;
# (3) backticked spans removed; (4) token drops (a bare `key:` / `key=`, `key = value`, `key : value`, `password is x`,
# `Authorization [:] Basic|Bearer|Token|Digest x` and `Bearer x` drop the value too, chained); (5) at
# least 3 words and 8 characters; (6) at most $cap code points (ALY-258: 140 for every text), cut at the last space
# (hard cut at $cap-1 when there is none or when that would leave fewer than 8) plus U+2026, so the ellipsis is inside the cap.
# This is the one cleaner of the reporter: a documented subset of the API scrubber (ALY-257 D-20), which stays authoritative.
def actcap: 140;
# ALY-263.6 (AC-09): the minimum of words and characters is a parameter; every text but the session label keeps 3 words and 8 characters.
def actclean($cap; $minw; $minc):
  if type != "string" then null else
    .[0:4096] | explode | map(if actws then 32 elif actbad then empty else . end) | implode
    | (try gsub("[\\p{Cc}\\p{Cf}\\p{Cs}]"; "") catch .)
    | gsub("`[^`]*(`|\\z)"; " ")
    | gsub("\\+?\\(?(?<![0-9A-Za-z])[0-9]([ .\\-()]{0,2}[0-9]){9,18}(?![0-9A-Za-z])"; " ")   # 10+ digits with separators/parentheses: account ids, CPF/CNPJ, phones, cards
    | [splits(" +") | select(length > 0)] as $t0
    # a path token is dropped (actdrop) and so are the Capitalized words that follow it, up to the next punctuation (D-20)
    | (reduce $t0[] as $w ({o: [], c: false};
        if ($w | actpath) then .c = true
        elif .c and ($w | test("\\A\\p{Lu}")) then (if ($w | test("[,;.!?:]\\z")) then .c = false else . end)
        else .o += [$w] | .c = false end) | .o) as $t
    | (reduce range(0; $t | length) as $k ({o: [], s: 0};
        $t[$k] as $w | ($t[$k + 1] // "") as $n
        | if .s > 0 then .s -= 1 | (if ($w | actscheme) or ($w | actbare) or ($w | actsep) then .s += 1 else . end)
          elif ($w | actcore | actwk) and ($n | ascii_downcase | IN("is","as")) then .s = 2   # `the key is x`, `session is x`: the whole-word names
          elif ($w | actbearer) then .s = 1
          elif ($w | actauth) and ($n | actscheme) then .s = 1   # the scheme, then (chained) its value
          elif ($w | actkv) then (if ($w | actbare) then .s = 1 else . end)
          elif ($w | actkey) and ($n | actsep) then .s = 1   # the separator, then (chained) the value
          elif ($w | actword) then (if ($n | ascii_downcase | IN("is","as")) then .s = 2 else .s = 1 end)
          elif ($w | actdrop) then .
          else .o += [$w] end)) as $r
    | ($r.o | join(" ")) as $p
    | if ($r.o | length) < $minw or ($p | length) < $minc then null
      elif ($p | length) <= $cap then $p
      else ($p | explode) as $e
        | ([range(0; $cap) | select($e[.] == 32)] | last) as $i
        | (if $i != null and $i >= 8 then $e[0:$i] else $e[0:($cap - 1)] end | implode | sub(" +\\z"; "")) + "\u2026"
      end
  end;
QEOF
)

# The jq programs of the question kind. Static text; nothing secret is ever in them.
QBODY_PROG='
def qc($c): actclean($c; 1; 1);
def okobj: type == "object";
(.tool_input.questions | arrays | .[0:4]) as $qs
| if ($qs | length) >= 1 and all($qs[]; okobj and (.options | arrays | length) >= 1 and all(.options[0:4][]; okobj)) then
    [$qs[] | {question: (.question | qc(400)), header: (.header | qc(40)), multiSelect: (.multiSelect == true),
              options: [.options[0:4][] | {label: (.label | qc(100)), description: (.description | qc(300))}]}] as $q
    | if all($q[]; .question != null and all(.options[]; .label != null)) then
        {session_hash: $s, kind: "question", hash: $h, risk: "normal", tool: "AskUserQuestion",
         questions: [$q[] | with_entries(select(.value != null)) | .options |= map(with_entries(select(.value != null)))]}
      else empty end
  else empty end'

# $mode v: prints "ok" and the sanitised `other` texts (answers order) when the decision is valid; $mode b: with $oth (the texts after
# NFC) prints the hook output. Both check everything, so a text that changed the check cannot slip through the second stage.
QANS_PROG='
def isint: type == "number" and . == floor and . >= 0 and . < 1000000;
def cleanother: explode | map(select((actbad or . == 8232 or . == 8233) | not)) | implode | (try gsub("[\\p{Cc}\\p{Cf}\\p{Cs}]"; "") catch .) | .[0:500];
def entryok($qs):
  type == "object" and ((keys - ["other", "picks", "q"]) | length) == 0 and has("q") and has("picks")
  and (.q | isint) and .q < ($qs | length)
  and (.picks | type) == "array" and all(.picks[]; isint) and ((.picks | unique | length) == (.picks | length))
  and (.q as $q | all(.picks[]; . < ($qs[$q].options | length)))
  and ((has("other") | not) or ((.other | type) == "string" and (.other | cleanother | length) > 0))
  and (.q as $q | ($qs[$q].multiSelect == true) as $m | (.picks | length) as $n | has("other") as $ot
       | if $m then ($n >= 1 or $ot) else (($n == 1 and ($ot | not)) or ($n == 0 and $ot)) end);
($o[0]) as $ti | ($ti.questions) as $qs | .data as $d
| if ($d | type) == "object" and $d.status == "answered" and ($d.decision | type) == "object" and ($d.decision | keys) == ["answers"]
     and ($ti | type) == "object" and ($qs | type) == "array" and ($qs | length) >= 1
     and all($qs[]; type == "object" and (.question | type) == "string" and (.options | type) == "array" and (.options | length) >= 1
                    and all(.options[]; type == "object" and (.label | type) == "string"))
     and ([$qs[].question] | unique | length) == ($qs | length)
     and ($d.decision.answers | type) == "array" and ($d.decision.answers | length) == ($qs | length)
     and all($d.decision.answers[]; entryok($qs))
     and ([$d.decision.answers[].q] | unique | length) == ($qs | length)
  then
    $d.decision.answers as $a
    | [range(0; $a | length) | select($a[.] | has("other"))] as $pos
    | [$pos[] | $a[.].other | cleanother] as $san
    | if $mode == "v" then "ok", $san[]
      elif ($oth | length) != ($san | length) then empty
      else
        ([range(0; $a | length) as $i | $a[$i] + {oi: ($pos | index($i))}] | sort_by(.q)
          | map(.q as $q | {key: $qs[$q].question,
                value: ([(.picks | sort)[] | $qs[$q].options[.].label] + (if .oi != null then [$oth[.oi]] else [] end) | join(","))})
          | from_entries) as $ans
        | {hookSpecificOutput: {hookEventName: "PermissionRequest", decision: {behavior: "allow", updatedInput: ($ti + {answers: $ans})}}}
      end
  else empty end'

# answer_question: the `answered` stage of a question request; prints at most one line, never anything else. $T/orig holds tool_input.
answer_question() {
  local v out
  [ -s "$T/orig" ] && [ -s "$T/resp" ] || return 0
  : >"$T/oth"
  v=$(head -c 65536 "$T/resp" | jq -r --arg mode v --slurpfile o "$T/orig" --argjson oth '[]' "$QCLEAN_DEFS
$QANS_PROG" 2>/dev/null) || return 0
  [ "${v%%$'\n'*}" = ok ] || return 0
  if [[ "$v" == *$'\n'* ]]; then
    printf '%s\n' "${v#*$'\n'}" >"$T/othraw" || return 0
    if command -v uconv >/dev/null 2>&1; then
      uconv -f utf-8 -t utf-8 -x any-nfc <"$T/othraw" >"$T/othnfc" 2>/dev/null || return 0
      [ "$(wc -l <"$T/othnfc" | tr -d ' ')" = "$(wc -l <"$T/othraw" | tr -d ' ')" ] || return 0
    else
      cat "$T/othraw" >"$T/othnfc" 2>/dev/null || return 0
    fi
    jq -R -c '.[0:500]' <"$T/othnfc" >"$T/oth" 2>/dev/null || return 0
  fi
  out=$(head -c 65536 "$T/resp" | jq -a -c --arg mode b --slurpfile o "$T/orig" --slurpfile oth "$T/oth" "$QCLEAN_DEFS
$QANS_PROG" 2>/dev/null) || return 0
  [ -n "$out" ] && [[ "$out" != *$'\n'* ]] || return 0
  printf '%s\n' "$out"
  dbg "printed"
  api_call POST "/api/live/requests/$RID/ack" 2 0
  return 0
}

main() {
  local F SID TOOL HASH SHASH KIND SEL line rem mt wstart dl exp_in st reason R rid ans exp

  _src="${BASH_SOURCE[0]}"
  case "$_src" in */*) ;; *) _src="./$_src" ;; esac
  [ -r "${_src%/*}/lib/credential.sh" ] || return 0
  . "${_src%/*}/lib/credential.sh"

  DIR="${CLAUDE_PLUGIN_DATA:-}"
  valid_dir_arg "$DIR" || return 0
  command -v jq >/dev/null 2>&1 || return 0
  command -v curl >/dev/null 2>&1 || return 0
  command -v mktemp >/dev/null 2>&1 || return 0
  command -v env >/dev/null 2>&1 || return 0
  command -v sleep >/dev/null 2>&1 || return 0
  have_sha || return 0
  UID_NOW=$(id -u 2>/dev/null) || return 0
  load_live_credential "$DIR" || return 0
  API="$LIVE_API"
  case "$API" in http://*) PROTO=(--proto '=http') ;; *) PROTO=(--proto '=https') ;; esac

  LIVE_DIR="$DIR/live"
  case "$LIVE_DIR" in *[\"\\]*) return 0 ;; esac   # the path goes into a curl config string
  [ ! -L "$LIVE_DIR" ] || return 0
  [ -e "$LIVE_DIR" ] || mkdir -m 700 "$LIVE_DIR" 2>/dev/null || [ -d "$LIVE_DIR" ] || return 0
  [ -n "$(find "$LIVE_DIR" -prune -type d -user "$UID_NOW" -perm 0700 -print 2>/dev/null)" ] || return 0
  # reporting switched off or disabled: nothing to do (fail safe: any entry counts)
  if [ -e "$LIVE_DIR/off" ] || [ -L "$LIVE_DIR/off" ] || [ -e "$LIVE_DIR/disabled" ] || [ -L "$LIVE_DIR/disabled" ]; then return 0; fi
  # SHD-03: stale temp entries of this script (a killed run leaves its directory with a decision body); best effort, silent
  find "$LIVE_DIR" -maxdepth 1 -name '.answer.*' -type d -mmin +10 -user "$UID_NOW" -exec rm -rf {} + 2>/dev/null || true
  find "$LIVE_DIR" -maxdepth 1 -name '.answer-backoff.*' -type f -mmin +10 -user "$UID_NOW" -exec rm -f {} + 2>/dev/null || true

  BACKOFFF="$LIVE_DIR/answer-backoff"
  DBGF="$LIVE_DIR/answer-debug.log"
  CFP=$(printf '%s' "$LIVE_TOKEN" | sha_hex) || return 0
  [[ "$CFP" =~ ^[0-9a-f]{64}$ ]] || return 0
  if backoff_active; then dbg "backoff active"; return 0; fi

  # the payload: read once, never on a command line
  INPUT=$(cat) || return 0
  F=$(printf '%s' "$INPUT" | jq -r '
    if type == "object" and .hook_event_name == "PermissionRequest"
       and (.session_id | type == "string" and test("\\A[A-Za-z0-9._:-]{1,128}\\z"))
       and (.tool_name | type == "string" and test("\\A[A-Za-z0-9_.:-]{1,128}\\z"))
       and (.tool_input | type == "object")
    then "\(.session_id)\n\(.tool_name)" else empty end' 2>/dev/null) || return 0
  [ -n "$F" ] || return 0
  SID=${F%%$'\n'*}; TOOL=${F#*$'\n'}
  SHASH=$(printf '%s' "$SID" | sha_hex) || return 0
  SEL=permission
  KIND=permission   # the placeholder risk is normal until slice .5
  if [ "$TOOL" = AskUserQuestion ]; then
    SEL=question; KIND=question
    # Detailed Live off (the reporter's markers; any entry counts, fail safe): the question texts cannot be sent, so do not open
    if [ -e "$LIVE_DIR/activity-off" ] || [ -L "$LIVE_DIR/activity-off" ] || [ -e "$LIVE_DIR/detailed-off" ] || [ -L "$LIVE_DIR/detailed-off" ]; then return 0; fi
  fi
  HASH=$(printf '%s' "$INPUT" | hash_of "$SEL") || return 0
  [[ "$HASH" =~ ^[0-9a-f]{64}$ ]] || return 0

  T=$(mktemp -d "$LIVE_DIR/.answer.XXXXXX" 2>/dev/null) || { T=""; return 0; }
  if [ "$SEL" = question ]; then
    printf '%s' "$INPUT" | jq -c '.tool_input' >"$T/orig" 2>/dev/null || return 0   # the ORIGINAL tool_input for the output stage
    printf '%s' "$INPUT" | jq -c --arg s "$SHASH" --arg h "$HASH" "$QCLEAN_DEFS
$QBODY_PROG" >"$T/body" 2>/dev/null || return 0
    [ -s "$T/body" ] || return 0   # a text the cleaner removed, no options...: no open
  else
    jq -n -c --arg s "$SHASH" --arg k "$KIND" --arg h "$HASH" --arg r normal --arg t "$TOOL" \
      '{session_hash: $s, kind: $k, hash: $h, risk: $r, tool: $t}' >"$T/body" 2>/dev/null || return 0
  fi
  INPUT=""
  dbg "open"

  api_call POST /api/live/requests 2 1
  rm -f "$T/body" 2>/dev/null || true
  if [ "$CRC" -ne 0 ] || [ -z "$HC" ]; then backoff_set 60; dbg "open failed curl"; return 0; fi
  case "$HC" in
    2??) ;;
    404)
      # ALY-268 final contract: a 404 with error.message.code run_not_found is NORMAL (the first tool call can open before any ingest
      # flush created the run): no backoff, the terminal decides. Any other 404 (missing endpoint, old API) backs off for 10 minutes.
      R=$(head -c 65536 "$T/resp" 2>/dev/null | jq -r '.error.message.code | strings' 2>/dev/null | head -n 1) || R=""
      if [ "$R" = run_not_found ]; then dbg "open run_not_found"; return 0; fi
      backoff_set 600; dbg "open status 404"; return 0 ;;
    405) backoff_set 600; dbg "open status 405"; return 0 ;;
    429) dbg "open status 429"; return 0 ;;
    *) backoff_set 60; dbg "open status $HC"; return 0 ;;
  esac
  R=$(head -c 65536 "$T/resp" 2>/dev/null | jq -r '
    if (.data | type) == "object" and (.data.id | type == "string" and test("\\A[A-Za-z0-9_-]{1,64}\\z")) and (.data.answerable | type) == "boolean"
    then "\(.data.id) \(.data.answerable) \((.data.expiresAt | strings | sub("\\.[0-9]+"; "") | sub("[+-]00:?00$"; "Z") | try fromdateiso8601 catch "bad") // "bad")"
    else empty end' 2>/dev/null) || R=""
  if [ -z "$R" ]; then backoff_set 60; dbg "open malformed"; return 0; fi
  rid=${R%% *}; ans=${R#* }; exp=${ans#* }; ans=${ans%% *}
  [[ "$rid" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { backoff_set 60; return 0; }
  if [ "$ans" != true ]; then dbg "not answerable"; return 0; fi
  RID="$rid"; PENDING=1   # the request is open from here: every later end of the script cancels it (no backoff for a bad expiresAt)

  # the deadline, in SECONDS since this script started: the smaller of the budget and the API's expiresAt. An expiresAt that is not a
  # sane future time (unparsable, before 1970, a non-UTC offset, more than a day away) gives deadline 0: no wait, the trap cancels.
  now_epoch || return 0
  dl="$BUDGET"
  if [[ "$exp" =~ ^[0-9]{1,12}$ ]] && [ "$exp" -gt "$NOW" ] && [ "$((exp - NOW))" -le 86400 ]; then
    exp_in=$((exp - NOW + SECONDS))
    [ "$exp_in" -ge "$dl" ] || dl="$exp_in"
  else
    dl=0; dbg "bad expiresAt"
  fi
  while :; do
    rem=$((dl - SECONDS))
    [ "$rem" -gt 1 ] || { dbg "deadline"; return 0; }
    mt=$((rem - 1)); [ "$mt" -le 30 ] || mt=30
    wstart=$SECONDS
    api_call GET "/api/live/requests/$RID/wait" "$mt" 0
    if [ "$CRC" -ne 0 ] || [ -z "$HC" ]; then
      # a chunk that ran out of time leaves the request pending (cancelled by the trap); any other failure is an API error
      [ "$CRC" = 28 ] || PENDING=0
      dbg "wait failed curl"; return 0
    fi
    case "$HC" in 2??) ;; *) PENDING=0; dbg "wait status $HC"; return 0 ;; esac
    st=$(head -c 65536 "$T/resp" 2>/dev/null | jq -r '
      if (.data | type) == "object" and (.data.status | type == "string") and (.data.status | IN("pending", "answered", "terminal", "expired"))
      then .data.status else empty end' 2>/dev/null) || st=""
    case "$st" in
      pending) dbg "wait pending" ;;
      answered) PENDING=0; dbg "wait answered"; [ "$SEL" != question ] || answer_question; return 0 ;;   # the permission kind is slice .5
      terminal|expired) PENDING=0; dbg "wait $st"; return 0 ;;
      *) PENDING=0; dbg "wait malformed"; return 0 ;;
    esac
    if [ "$SECONDS" -le "$wstart" ]; then   # an immediate `pending`: do not spin
      sleep 1 & SPID=$!
      wait "$SPID" && true || true
      SPID=""
    fi
  done
}

trap cleanup EXIT
trap 'exit 0' INT TERM HUP
{ main; } 2>/dev/null
exit 0
