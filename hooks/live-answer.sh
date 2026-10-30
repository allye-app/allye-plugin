#!/bin/bash
# Claude Code blocking PermissionRequest hook of the Live return channel (ALY-269, D-07). Slice ALY-269.3: the answer CLIENT.
# It opens a request on the Allye API and waits for the answer. Slice .5 adds the permission path: risk, D-08 phrase and the
# PermissionRequest output (the question path is slice .4). stdin = the Claude Code hook JSON, stdout = hook output.
#
# Contract (BR-02, AC-16): the terminal keeps the last word. On any doubt the script exits 0 with no output; every exit below is
# a literal `exit 0`, there is no `set -e`, and a top-level ERR trap ends with exit 0. stderr is never written (`exec 2>/dev/null`),
# stdout gets one line only for a strictly validated permission decision (permission_answered). Runtime: bash 3.2+, curl, jq, sha256sum or shasum.
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
# Open (AC-06): POST /api/live/requests {session_hash, kind, hash, risk, tool[, phrase]} (no tu, never; `after` is slice .10), --max-time 2.
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

# ─── ALY-269.5 / .11: the permission path (AC-04, AC-07, AC-09, BR-01, D-08, D-09, D-13) ───
# The D-08 phrase grammar of hooks/live-report.sh (lines of ALY-217.6, ALY-258, ALY-263.3/.9: the cleaner actclean and the constant
# templates of tooltpl), copied unchanged so the request carries the same phrase the reporter shows; `toolphrase` is its entry point and
# reads .tool_name / .tool_input of the payload. $txt is "1". Nothing of the raw command, path or input is sent: only the cleaned
# description or a constant template with at most one basename or one Allye key. The Allye action name is never echoed by it.
PHRASE_DEFS=$(cat <<'JQDEFS'
def sre($r): type == "string" and test($r);
def keyok:  sre("\\A[A-Z][A-Z0-9]{1,9}-[0-9]+(\\.[0-9]+)?\\z");
def mcpname: (.tool_name | sre("\\Amcp__[A-Za-z0-9_-]{1,200}\\z"));
def allyesrv: mcpname and ((.tool_name | split("__")) as $p | ($p | length) >= 3 and ($p[1] | . == "allye" or endswith("_allye")));
# ─── ALY-217.6: the activity phrase (BR-10, BR-11, D-23, D-24) ───
# Code points stripped (D-04 forbidden set, plus the other format characters the API refuses: \p{Cf}, U+034F, the
# variation selectors and the tag characters; U+FFFD and surrogates as a safety net) and code points read as a space.
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
def actphrase($cap): actclean($cap; 3; 8);
# BR-10 (D-24 a, b, c): the one field read per tool; nothing while the activity-off flag exists.
# $txt is "1" unless texts are off (the activity-off flag; ALY-258.3 adds detailed:false): then no activity, no desc, no stash.
def actof:
  if $txt != "1" then null
  elif .tool_name | IN("Bash","Agent","Task") then ((.tool_input | objects | .description) // null) | actphrase(actcap)
  elif .tool_name == "TodoWrite" then [.tool_input | objects | .todos | arrays | .[] | objects | select(.status == "in_progress")] | .[0] | (objects | .activeForm) // null | actphrase(actcap)
  else null end;
def namedeny: ascii_downcase | test("\\A\\.env|credential|secret|token|passw|private|\\.pem\\z|\\.key\\z|id_(rsa|ed25519|ecdsa)|\\.p12\\z|\\.pfx\\z|kubeconfig|netrc|npmrc|pairing|hook-|service-account|keystore|\\.tfstate|\\.kdbx");
def deftbase: if type == "string" and test("\\A[A-Za-z0-9._-]{1,60}\\z") and test("[A-Za-z]") and (test("\\A\\.+\\z") | not) and (namedeny | not) and (namedrop | not) then . else null end;
def pathbase: if type == "string" then (split("/") | last) | deftbase else null end;
def filetpl($verb; $fallback; $f): ((.tool_input | objects | .[$f]) | pathbase) as $b | if $b != null then $verb + " " + $b else $fallback end;
def crewroles: ["armorer","architect","copilot","dispatcher","medic","navigator","optimizer","pilot","recon","shield","strategist","watcher"];
def skilltpl: ((.tool_input | objects | (.skill // .name)) | if type == "string" then (capture("\\A(allye:)?bridge-(?<r>[a-z]+)\\z")? // null) | (objects | .r) else null end) as $r
  | if $r != null and ($r | IN(crewroles[])) then "Load the " + $r + " skill" else null end;
def keyslot($f): ((.tool_input | objects | .[$f]) | if type == "string" and keyok then . else null end);
def mcptpl:
  if allyesrv | not then null else
    (.tool_name | split("__") | last) as $sfx
    | ((.tool_input | objects | .action) // "") as $a
    | if ($a | type) != "string" then null
      elif $sfx == "tasks" and ($a | IN("task_start","task_submit","task_complete")) then
        ({task_start: "Start", task_submit: "Submit", task_complete: "Complete"}[$a]) as $v | (keyslot("task")) as $k | if $k != null then $v + " task " + $k else $v + " a task" end
      elif $sfx == "specs" and ($a | IN("spec_get","spec_context")) then (keyslot("spec")) as $k | if $k != null then "Read spec " + $k else "Read a spec" end
      elif $sfx == "kb" and ($a | IN("kb_read","kb_search","kb_tree")) then "Read a KB page"
      elif $sfx == "kb" and ($a | IN("kb_update","kb_section","kb_create")) then "Update a KB page"
      else null end
  end;
def bscript($s): if $s == "test" then "Run tests" elif $s == "lint" then "Lint" elif $s == "typecheck" then "Typecheck" elif $s == "build" then "Build"
  elif $s == "vitest" then "Run vitest" elif $s == "jest" then "Run jest" elif $s == "eslint" then "Lint" elif $s == "tsc" then "Typecheck" else null end;
def dropvars: if length > 0 and (.[0] | test("\\A[A-Za-z_][A-Za-z0-9_]*=")) then (.[1:] | dropvars) else . end;
def bwcls:
  (.[0] // "" | sub("\\A.*/"; "")) as $a | (.[1] // "") as $b
  | if $a == "vitest" then "Run vitest" elif $a == "jest" then "Run jest" elif $a == "eslint" or $a == "lint" then "Lint"
    elif $a == "tsc" then (if (.[1:] | any(. == "-b" or . == "--build")) then "Build" else "Typecheck" end)
    elif $a == "typecheck" then "Typecheck" elif $a == "build" then "Build"
    elif $a == "git" then (if $b == "diff" then "Read the diff" elif $b == "status" then "Check git status" else null end)
    elif $a == "make" then (if $b == "build" then "Build" else null end)
    elif $a == "node" then (if $b | startswith("--test") then "Run tests" else null end)
    elif $a | IN("npm","pnpm","yarn","bun") then bscript(if $b == "run" then (.[2] // "") else $b end)
    elif $a | IN("npx","bunx","pnpx") then (.[1:] | bwcls)
    else null end;
def bashtpl: ((.tool_input | objects | .command) | if type == "string" then .[0:4096] | [splits("[ \t\r\n]+") | select(length > 0)] | dropvars | bwcls else null end) // "Run a command";
def tooltpl:
  if (.tool_name | type) != "string" then null
  elif .tool_name == "Read" then filetpl("Read"; "Read a file"; "file_path")
  elif .tool_name | IN("Edit","MultiEdit") then filetpl("Edit"; "Edit a file"; "file_path")
  elif .tool_name == "Write" then filetpl("Write"; "Edit a file"; "file_path")
  elif .tool_name == "NotebookEdit" then filetpl("Edit"; "Edit a file"; "notebook_path")
  elif .tool_name == "Grep" then "Search the code"
  elif .tool_name == "Glob" then "Find files"
  elif .tool_name == "Skill" then skilltpl
  elif .tool_name == "Bash" then bashtpl
  elif .tool_name | startswith("mcp__") then mcptpl
  else null end;
def toolphrase: if $txt != "1" then null else ([actof // tooltpl] | .[0]) end;
JQDEFS
)

# classify_risk (D-09, AC-04, ALY-269.11): sets RISK from $INPUT. The plugin can only RAISE the API's own risk, so every doubt is high.
# The jq part decides by tool; a path tool yields its candidate paths and the shell resolves them (symlinks followed, `..` removed).
#   Bash, unknown tools, every mcp__ tool other than the Allye plugin server (mcp__plugin_allye_allye__<tool>): high.
#   Allye tools are one tool per area with an `action` input (ALY-269.11): normal ONLY for a STRING action found in the read-only list
#   of THAT tool (confirmed against the allye-mcp tool definitions); a missing, non-string, unknown or write action is high. The action
#   is used here and nowhere else: it is not sent, not in `tool`, not in the phrase.
#   Read, Glob, Grep, Edit, Write, NotebookEdit, MultiEdit: normal only when every path they name resolves INSIDE the project
#   root (project_root; the payload cwd only joins RELATIVE paths and must itself be inside the root) and is not protected; otherwise high. Glob also checks the literal base of its pattern.
# ACCEPTED LIMITATION (SHD-04): the server name cannot be checked from the payload. A repository .mcp.json that declares a server named
# `plugin_allye_allye` yields the same tool prefix and is indistinguishable from the Allye plugin; its read-looking actions would be normal.
# Recorded for the PR and the docs; no pairing-marker check is built. The API still recomputes and keeps any higher risk.
RISK_JQ='
def clean: type == "string" and length > 0 and length <= 4096 and (test("[\\p{Cc}\\p{Cf}\\p{Cs}  ]") | not);
def readonly: {
  projects: ["project_list","project_get","project_overview","app_list","project_resolve"],
  epics: ["epic_list","epic_get"],
  specs: ["spec_list","spec_get","spec_context","spec_validate","spec_diff","spec_versions"],
  tasks: ["task_list","task_get","task_mine","task_next"],
  team: ["team_list","team_current","team_members","team_help"],
  intelligence: ["memory_search","memory_get","memory_list","memory_graph","memory_relations","memory_preferences"],
  kb: ["kb_spaces","kb_tree","kb_search","kb_read","kb_history"],
  skills: ["skill_list","skill_get","skill_list_revisions"],
  api_catalog: ["api_catalog_search","api_catalog_list","api_catalog_get"],
  productivity: ["todo_list","todo_get","todo_stats","todo_search","todo_overdue","todo_upcoming","todo_categories","todo_tags","todo_help"]
};
def cand($cwd): if startswith("/") then . elif startswith("~") then null else $cwd + "/" + . end;
def litbase: split("/") | reduce .[] as $c ({o: [], stop: false}; if .stop or ($c | test("[*?\\[{]")) then .stop = true else .o += [$c] end) | .o | join("/");
.tool_name as $t | .cwd as $cwd | (.tool_input | objects) as $i
| if $t == "Bash" then "high"
  elif ($t | type) != "string" then "high"
  elif ($t | startswith("mcp__")) then
    if ($t | test("\\Amcp__plugin_allye_allye__[A-Za-z0-9_-]{1,40}\\z")) then
      ($t | ltrimstr("mcp__plugin_allye_allye__")) as $n
      | if $n == "allye_health_check" then "normal"
        else ($i.action // null) as $a
          | if ($a | type) == "string" and ((readonly[$n] // []) | index($a)) != null then "normal" else "high" end end
    else "high" end
  elif ($t | IN("Read","Edit","Write","MultiEdit","NotebookEdit","Grep","Glob")) then
    if ($cwd | clean | not) or ($cwd | startswith("/") | not) then "high" else
      (if $t == "NotebookEdit" then "notebook_path" elif $t | IN("Grep","Glob") then "path" else "file_path" end) as $k
      | ($t | IN("Grep","Glob")) as $opt
      | ($i[$k]) as $v
      | (if ($i | has($k) | not) then (if $opt then $cwd else null end) elif ($v | clean) then ($v | cand($cwd)) else null end) as $c1
      | (if $t == "Glob" and ($i | has("pattern")) then
           (if ($i.pattern | clean) and ($i.pattern | startswith("~") | not) then (($i.pattern | litbase) as $b | (if $i.pattern | startswith("/") then (if $b == "" then "/" else $b end) else ($c1 // "") + "/" + $b end)) else null end)
         else "" end) as $c2
      | if $c1 == null or $c2 == null then "high"
        else ((if $opt then "path" else "pathw" end), $cwd, $c1, (if $c2 == "" then empty else $c2 end)) end
    end
  else "high" end'

resolve_path() {  # sets RP to the absolute path with symlinks resolved (a missing tail is kept lexically); fails when no tool resolves it
  RP=""
  if command -v realpath >/dev/null 2>&1; then RP=$(realpath -m -- "$1" 2>/dev/null) || RP=""; fi
  if [ -z "$RP" ] && command -v readlink >/dev/null 2>&1; then RP=$(readlink -f -- "$1" 2>/dev/null) || RP=""; fi
  [ -n "$RP" ] && [ "${RP#/}" != "$RP" ]
}
protected_rel() {  # REL (relative to the project root, resolved): 0 when protected
  local lc b
  lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]') || return 0
  case "/$lc" in */.*) return 0 ;; esac   # .claude/, .git/, .github/, .mcp.json, .envrc, any dotfile or dot-directory component
  case "/$lc/" in */scripts/*) return 0 ;; esac   # a scripts directory at ANY depth
  b=${lc##*/}
  # manifests, lockfiles, build and CI files (ALY-269 SHD-03: fail closed); compared case-insensitively at any depth
  case "$b" in
    package.json|package-lock.json|npm-shrinkwrap.json|yarn.lock|pnpm-lock.yaml|bun.lock|bun.lockb|cargo.toml|cargo.lock|go.mod|go.sum|pyproject.toml|poetry.lock|requirements*.txt|gemfile|gemfile.lock|composer.json|composer.lock|makefile|gnumakefile|dockerfile*|jenkinsfile) return 0 ;;
    azure-pipelines.yml|azure-pipelines.yaml|bitbucket-pipelines.yml|cloudbuild.yaml|cloudbuild.yml|taskfile*|justfile|docker-compose*|setup.py|setup.cfg|tox.ini|pom.xml|build.gradle*|settings.gradle*|cmakelists.txt|rakefile|pipfile*|deno.json*|bunfig.toml|procfile) return 0 ;;
  esac
  return 1
}
# project_root CWDRESOLVED: sets ROOT_DIR. SHD-01: the root is NOT the payload cwd (a Bash `cd .git/hooks` persists in the cwd). It is
# $CLAUDE_PROJECT_DIR (set by Claude Code; resolved; used ONLY here for classification, never for the API origin or the credential, D-15);
# unset or unresolvable: the nearest ancestor of the resolved cwd that holds `.git` or `.claude`; none: no root (high).
project_root() {
  local d="$1" e="${CLAUDE_PROJECT_DIR:-}"
  ROOT_DIR=""
  if [ -n "$e" ]; then
    case "$e" in /*) ;; *) e="" ;; esac
    case "$e" in *[![:print:]]*) e="" ;; esac
    if [ -n "$e" ] && resolve_path "$e" && [ -d "$RP" ]; then ROOT_DIR=$RP; return 0; fi
  fi
  while :; do
    if [ -e "$d/.git" ] || [ -L "$d/.git" ] || [ -e "$d/.claude" ] || [ -L "$d/.claude" ]; then ROOT_DIR=$d; return 0; fi
    [ "$d" != / ] || return 1
    d=${d%/*}; [ -n "$d" ] || d=/
  done
}
classify_risk() {
  local R cls="" cwd="" cwdr root cand p rel n=0 line
  RISK=high
  R=$(printf '%s' "$INPUT" | jq -r "$RISK_JQ" 2>/dev/null) || return 0
  [ -n "$R" ] || return 0
  while IFS= read -r line; do
    n=$((n + 1))
    case "$n" in
      1) cls=$line
         case "$cls" in
           normal) RISK=normal; return 0 ;;
           path|pathw) ;;
           *) return 0 ;;
         esac ;;
      2) cwd=$line
         resolve_path "$cwd" || return 0
         [ -d "$RP" ] || return 0
         cwdr=$RP
         project_root "$cwdr" || return 0
         root=$ROOT_DIR
         [ "$root" != / ] && [ -d "$root" ] || return 0
         case "$cwdr" in "$root"|"$root"/*) ;; *) return 0 ;; esac ;;   # the cwd must be inside the project
      *) cand=$line
         resolve_path "$cand" || return 0
         p=$RP
         case "$p" in
           "$root") rel="" ;;
           "$root"/*) rel=${p#"$root"/} ;;
           *) return 0 ;;
         esac
         if [ -z "$rel" ]; then [ "$cls" = path ] || return 0   # the project directory itself: only a read-only search may name it
         else ! protected_rel "$rel" || return 0; fi ;;
    esac
  done <<<"$R"
  [ "$n" -ge 3 ] || return 0
  RISK=normal
  return 0
}

# phrase_of: sets PHRASE to the D-08 phrase of $INPUT, or "" (then `phrase` is omitted). Never longer than 300, never multi-line.
phrase_of() {
  PHRASE=""
  # SHD-02 (BR-03): texts off = activity-off or detailed-off flag in the live dir (any entry counts, as texts_off of the reporter): no phrase
  if [ -e "$LIVE_DIR/activity-off" ] || [ -L "$LIVE_DIR/activity-off" ] || [ -e "$LIVE_DIR/detailed-off" ] || [ -L "$LIVE_DIR/detailed-off" ]; then return 0; fi
  PHRASE=$(printf '%s' "$INPUT" | jq -r --arg txt 1 "$PHRASE_DEFS"$'\n''(toolphrase // empty) | select(type == "string") | .[0:300]' 2>/dev/null) || PHRASE=""
  case "$PHRASE" in *$'\n'*) PHRASE="" ;; esac
  return 0
}

# DECIDE_JQ (AC-07, AC-09, BR-02): the ONLY producer of the PermissionRequest output. It prints nothing unless status is `answered`
# and the decision is an object whose keys are `behavior` (exactly "allow" or "deny") and optionally `message` (a string). The message
# is cleaned: ANSI escape sequences removed, control, bidi, zero-width, tag and other invisible code points (the reporter's actbad)
# stripped, whitespace to single spaces, 200 code points at most. NFC runs through `uconv -x any-nfc` only when that tool is on the
# PATH (none is guaranteed): without it, strip and cap only. A decision `allow` on a request whose OWN risk is high is dropped here (fail closed,
# BR-02: the API enforces deny-only for high, this is the plugin-side check). Never updatedPermissions, updatedInput or an "always" rule.
DECIDE_JQ='
def msgclean:
  gsub("\u001b\\[[0-9;?]*[ -/]*[@-~]"; "") | gsub("\u001b\\][^\u0007\u001b]*(\u0007|\u001b\\\\)"; "")
  | .[0:2000] | explode | map(if actws then 32 elif actbad then empty else . end) | implode
  | gsub(" +"; " ") | sub("\\A "; "") | sub(" \\z"; "") | .[0:200] | sub(" \\z"; "");
.data | objects | select(.status == "answered") | .decision | objects
| select(((keys - ["behavior", "message"]) == []) and (.behavior | IN("allow", "deny")) and ((has("message") | not) or (.message | type == "string")))
| select(.behavior == "deny" or $risk != "high")
| (if has("message") then (.message | msgclean) else "" end) as $m
| {hookSpecificOutput: {hookEventName: "PermissionRequest", decision: ({behavior: .behavior} + (if $m != "" then {message: $m} else {} end))}}'

# permission_answered: validates $T/resp and prints the decision line (one printf, after every check). Returns 1 when nothing was printed.
permission_answered() {
  local O
  O=$(head -c 65536 "$T/resp" 2>/dev/null | jq -c --arg risk "$RISK" "$PHRASE_DEFS"$'\n'"$DECIDE_JQ" 2>/dev/null) || return 1
  [ -n "$O" ] || return 1
  case "$O" in *$'\n'*) return 1 ;; '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"'*) ;; *) return 1 ;; esac
  # SHD-05: NFC of the message only when uconv is on the PATH (a failure, or a changed line count, prints nothing); without it strip+cap stay
  if command -v uconv >/dev/null 2>&1 && [ "$(printf '%s' "$O" | jq -r '.hookSpecificOutput.decision | has("message")')" = true ]; then
    local M N
    M=$(printf '%s' "$O" | jq -j '.hookSpecificOutput.decision.message') || return 1
    N=$(printf '%s' "$M" | uconv -f utf-8 -t utf-8 -x any-nfc 2>/dev/null) || return 1
    case "$N" in ''|*$'\n'*) return 1 ;; esac
    O=$(printf '%s' "$O" | jq -c --rawfile m <(printf '%s' "$N") '.hookSpecificOutput.decision.message = $m') || return 1
    case "$O" in *$'\n'*) return 1 ;; esac
  fi
  printf '%s\n' "$O"
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
  [[ "$TOOL" =~ ^[A-Za-z0-9_.:-]{1,64}$ ]] || return 0   # the API's pattern for `tool`
  SEL=permission
  KIND=permission   # slice .4 sets question for AskUserQuestion
  RISK=normal; PHRASE=""   # a question keeps the placeholder risk until slice .4
  [ "$TOOL" != AskUserQuestion ] || SEL=question
  HASH=$(printf '%s' "$INPUT" | hash_of "$SEL") || return 0
  [[ "$HASH" =~ ^[0-9a-f]{64}$ ]] || return 0
  if [ "$SEL" = permission ]; then
    classify_risk; phrase_of
    # SHD-06: another server's tool name is sent as the literal `mcp` (like the reporter's redtool); the API recomputes (unknown = high)
    case "$TOOL" in mcp__*) [[ "$TOOL" =~ ^mcp__plugin_allye_allye__[A-Za-z0-9_-]{1,40}$ ]] || TOOL=mcp ;; esac
  fi   # ALY-269.5: risk and D-08 phrase from the payload, then it is dropped
  INPUT=""

  T=$(mktemp -d "$LIVE_DIR/.answer.XXXXXX" 2>/dev/null) || { T=""; return 0; }
  # the phrase travels on stdin (never argv); `phrase` is omitted when empty
  printf '%s' "$PHRASE" | jq -R -s -c --arg s "$SHASH" --arg k "$KIND" --arg h "$HASH" --arg r "$RISK" --arg t "$TOOL" \
    '{session_hash: $s, kind: $k, hash: $h, risk: $r, tool: $t} + (if . != "" then {phrase: .} else {} end)' >"$T/body" 2>/dev/null || return 0
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
      answered)   # ALY-269.5: never cancel after answered; print the permission decision, then ack (the result is ignored)
        PENDING=0; dbg "wait answered"
        if [ "$SEL" = permission ] && permission_answered; then api_call POST "/api/live/requests/$RID/ack" 2 0; dbg "ack sent"; fi
        return 0 ;;
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
