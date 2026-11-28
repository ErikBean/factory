#!/usr/bin/env bash
# Tests for platform/github/repo-rulesets.sh against a stub gh: creating
# rulesets, leaving existing ones alone, printing how they differ, and
# replacing them with --update only when the admin says yes and the required
# check isn't changing by accident.
set -euo pipefail

script="$(cd "$(dirname "$0")/../.." && pwd)/platform/github/repo-rulesets.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failures=0

# The stub answers the calls the script makes from files under $STATE/<repo>/,
# and logs each write to $STATE/log, with its body in $STATE/<verb>-<repo>-<id>.json.
mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = api ] || exit 9
shift
method=GET
if [ "$1" = -X ]; then method=$2; shift 2; fi
path=$1
case "$method $path" in
  "GET user") echo admin ;;
  GET\ repos/ErikBean/*/rulesets\?includes_parents=false)
    repo=${path#repos/ErikBean/}; repo=${repo%%/*}
    cat "$STATE/$repo/list" 2>/dev/null || true ;;
  GET\ repos/ErikBean/*/rulesets/*)
    repo=${path#repos/ErikBean/}; repo=${repo%%/*}
    cat "$STATE/$repo/${path##*/}.json" ;;
  GET\ repos/ErikBean/*/rules/branches/main) echo "stub" ;;
  POST\ repos/ErikBean/*/rulesets)
    repo=${path#repos/ErikBean/}; repo=${repo%%/*}
    body=$(cat); name=$(node -p 'JSON.parse(process.argv[1]).name' "$body")
    echo "POST $repo $name" >>"$STATE/log"; printf '%s' "$body" >"$STATE/POST-$repo-$name.json" ;;
  PUT\ repos/ErikBean/*/rulesets/*)
    repo=${path#repos/ErikBean/}; repo=${repo%%/*}; id=${path##*/}
    echo "PUT $repo $id" >>"$STATE/log"; cat >"$STATE/PUT-$repo-$id.json" ;;
  *) echo "stub gh: unexpected $method $path" >&2; exit 9 ;;
esac
STUB
chmod +x "$work/bin/gh"

# A repo as GitHub returns it to an admin, with the fields the script doesn't
# set: ids, links, required_reviewers. $2 is the required check, $3 the
# main-review ruleset's require_last_push_approval.
make_repo() {
  local dir="$STATE/$1"
  mkdir -p "$dir"
  printf '101 main\n102 main-review\n' >"$dir/list"
  cat >"$dir/101.json" <<JSON
{"id":101,"name":"main","target":"branch","source_type":"Repository","enforcement":"active",
 "conditions":{"ref_name":{"exclude":[],"include":["~DEFAULT_BRANCH"]}},"bypass_actors":[],
 "rules":[{"type":"pull_request","parameters":{"required_approving_review_count":0,"dismiss_stale_reviews_on_push":false,"required_reviewers":[],"require_code_owner_review":false,"require_last_push_approval":false,"required_review_thread_resolution":false,"require_extra_approval_for_unattributed_changes":true,"allowed_merge_methods":["merge","squash","rebase"]}},
  {"type":"required_status_checks","parameters":{"strict_required_status_checks_policy":false,"do_not_enforce_on_create":false,"required_status_checks":[{"context":"$2","integration_id":15368}]}},
  {"type":"non_fast_forward"}],
 "node_id":"x","_links":{}}
JSON
  cat >"$dir/102.json" <<JSON
{"id":102,"name":"main-review","target":"branch","source_type":"Repository","enforcement":"active",
 "conditions":{"ref_name":{"exclude":[],"include":["~DEFAULT_BRANCH"]}},
 "bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"pull_request"}],
 "rules":[{"type":"pull_request","parameters":{"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true,"required_reviewers":[],"require_code_owner_review":true,"require_last_push_approval":$3,"required_review_thread_resolution":false,"require_extra_approval_for_unattributed_changes":true,"allowed_merge_methods":["merge","squash","rebase"]}}],
 "node_id":"y","_links":{}}
JSON
}

# Runs the script in a fresh state with $1 as the admin's answers, the rest as
# its arguments. Leaves its output in $out and its exit code in $code.
run() {
  local answers=$1; shift
  set +e
  out="$(printf '%s' "$answers" | PATH="$work/bin:$PATH" STATE="$STATE" "$script" "$@" 2>&1)"
  code=$?
  set -e
}

fresh() { STATE="$work/state-$1"; mkdir -p "$STATE"; : >"$STATE/log"; }

fail() { echo "  $1" >&2; printf '    | %s\n' "${out//$'\n'/$'\n    | '}" >&2; failures=$((failures + 1)); }
has() { grep -qF -- "$1" <<<"$out" || fail "$2: output lacks: $1"; }
log_is() { [ "$(cat "$STATE/log")" = "$1" ] || fail "$2: writes were [$(tr '\n' ';' <"$STATE/log")], expected [$1]"; }

# A new repo gets both rulesets, and main-review lets the developer approve their own push.
fresh new
run "" my-app
[ "$code" = 0 ] || fail "new repo: exit $code"
log_is "POST my-app main
POST my-app main-review" "new repo"
node -e 'const r=JSON.parse(require("fs").readFileSync(process.argv[1]));process.exit(r.rules[0].parameters.require_last_push_approval===false?0:1)' \
  "$STATE/POST-my-app-main-review.json" || fail "new repo: main-review still requires last-push approval"

# A repo that already matches: nothing written, both up to date.
fresh same
make_repo same "test / test" false
run "" same
[ "$code" = 0 ] || fail "matching repo: exit $code"
has "main is up to date" "matching repo"
has "main-review is up to date" "matching repo"
log_is "" "matching repo"

# A repo with last-push approval on, without --update: the difference is
# printed and nothing is written.
fresh old
make_repo old "test / test" true
run "" old
[ "$code" = 0 ] || fail "old repo: exit $code"
has "main-review differs" "old repo"
has '-        "require_last_push_approval": true,' "old repo"
has '+        "require_last_push_approval": false,' "old repo"
has "Run with --update" "old repo"
log_is "" "old repo"

# With --update and a yes, only main-review is replaced, with the script's version.
fresh yes
make_repo old "test / test" true
run "y" --update old
[ "$code" = 0 ] || fail "--update yes: exit $code"
log_is "PUT old 102" "--update yes"
grep -q '"require_last_push_approval": false' "$STATE/PUT-old-102.json" || fail "--update yes: PUT body keeps last-push approval"

# With --update and anything but yes, nothing is replaced.
fresh no
make_repo old "test / test" true
run "n" --update old
log_is "" "--update no"
has "Left as it is." "--update no"

# The factory's check is "test": --update without --check won't change it.
fresh check
make_repo factory "test" false
run "y" --update factory
[ "$code" = 1 ] || fail "check change: exit $code, expected 1"
has "it would change the required check" "check change"
log_is "" "check change"

# With --check given, the check matches and main is left alone.
fresh check-given
make_repo factory "test" true
run "y" --update --check test factory
[ "$code" = 0 ] || fail "--check test: exit $code"
has "main is up to date" "--check test"
log_is "PUT factory 102" "--check test"

if [ "$failures" -gt 0 ]; then
  echo "repo-rulesets: $failures failed" >&2
  exit 1
fi
echo "repo-rulesets: all passed"
