#!/usr/bin/env bash
# Run this yourself, signed in to gh as your own GitHub user (not the agents' app).
# Gives each repo named on the command line the factory's two rulesets on its
# default branch, the same as the factory and its apps have:
#   main         a pull request and a passing required check, no force
#                pushes, and no bypass for anyone. The check defaults to
#                "test / test", the name a factory-built app's CI reports: its
#                test job calls the factory's app-ci.yml, and GitHub names such
#                checks "<caller job> / <called job>".
#   main-review  a code owner's approval, dismissed when anyone pushes after
#                it. A GitHub App can't be a code owner, so the agents can't
#                approve their own pull requests. The developer may approve a
#                branch they updated themselves: with one developer there's no
#                one else to approve it. Repository admins may bypass the
#                ruleset, through a pull request only.
#
# A repo that already has a ruleset keeps it: the script prints how it differs
# from what the script would set. With --update, it shows the difference and
# asks before replacing the ruleset. A replacement is the whole ruleset, so:
#   - A bypass list fixed by hand in Settings goes back to the script's.
#     Check it afterwards, as the note at the end says.
#   - A required check the repo has that isn't --check's would be replaced,
#     and every merge would wait for a check that never reports. So the
#     script won't change the check unless --check is given.
# Safe to re-run: without --update it changes nothing a repo already has.
#
#   platform/github/repo-rulesets.sh my-new-app                    # requires "test / test"
#   platform/github/repo-rulesets.sh --check test factory          # the factory's own CI job is "test"
#   platform/github/repo-rulesets.sh --update jello-world clams-casino
#   platform/github/repo-rulesets.sh --update --check test factory
set -euo pipefail

owner=ErikBean
check="test / test"
check_given=false
update=false
repos=()
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check=${2:?--check needs a check name}; check_given=true; shift 2 ;;
    --update) update=true; shift ;;
    -*) echo "Unknown option: $1" >&2; exit 2 ;;
    *) repos+=("$1"); shift ;;
  esac
done
[ ${#repos[@]} -gt 0 ] || { echo "Usage: $0 [--update] [--check <name>] <repo>..." >&2; exit 2; }
[[ "$check" =~ ^[A-Za-z0-9\ /._-]+$ ]] || { echo "Unexpected characters in check name: $check" >&2; exit 2; }
# env runs the gh program from PATH, not this function, without the agents' token.
gh() { env -u GH_TOKEN -u GITHUB_TOKEN gh "$@"; }

login="$(gh api user --jq .login)" || { echo "gh isn't signed in as you: run gh auth login" >&2; exit 1; }
echo "Signed in as: $login"
echo "Required check on main: $check"

main_ruleset='{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "require_extra_approval_for_unattributed_changes": true,
        "allowed_merge_methods": ["merge", "squash", "rebase"] } },
    { "type": "required_status_checks", "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [ { "context": "'"$check"'" } ] } },
    { "type": "non_fast_forward" }
  ]
}'

review_ruleset='{
  "name": "main-review",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [ { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "pull_request" } ],
  "rules": [
    { "type": "pull_request", "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "require_extra_approval_for_unattributed_changes": true } }
  ]
}'

# Prints a ruleset in a form the script's own can be compared with: only the
# fields the script sets, keys sorted. Rules the script doesn't set are kept
# whole, so the difference shows them. Reads the ruleset on stdin and the
# script's version as the first argument.
shape() {
  node -e '
    const want = JSON.parse(process.argv[1]);
    const have = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const pick = (o, keys) => Object.fromEntries(keys.filter((k) => o && k in o).map((k) => [k, o[k]]));
    const rules = [];
    for (const w of want.rules) {
      for (const r of (have.rules || []).filter((r) => r.type === w.type)) {
        if (!w.parameters) { rules.push(r); continue; }
        const p = pick(r.parameters, Object.keys(w.parameters));
        if (p.required_status_checks) p.required_status_checks = p.required_status_checks.map((c) => ({ context: c.context }));
        rules.push({ type: r.type, parameters: p });
      }
    }
    for (const r of have.rules || []) if (!want.rules.some((w) => w.type === r.type)) rules.push(r);
    const out = {
      ...pick(have, ["name", "target", "enforcement", "conditions"]),
      bypass_actors: (have.bypass_actors || []).map((a) => pick(a, ["actor_id", "actor_type", "bypass_mode"])),
      rules,
    };
    const sort = (v) => Array.isArray(v) ? v.map(sort)
      : v && typeof v === "object" ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, sort(v[k])])) : v;
    console.log(JSON.stringify(sort(out), null, 2));
  ' "$1"
}

# The required checks in a shaped ruleset, one per line.
checks_of() {
  node -e '
    const r = JSON.parse(require("fs").readFileSync(0, "utf8"));
    for (const x of r.rules) for (const c of (x.parameters && x.parameters.required_status_checks) || []) console.log(c.context);
  '
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
status=0

for repo in "${repos[@]}"; do
  echo
  echo "== $owner/$repo"
  existing="$(gh api "repos/$owner/$repo/rulesets?includes_parents=false" --jq '.[] | "\(.id) \(.name)"')"
  for pair in "main:$main_ruleset" "main-review:$review_ruleset"; do
    name="${pair%%:*}"
    want="${pair#*:}"
    id="$(awk -v n="$name" '$2 == n { print $1; exit }' <<<"$existing")"
    if [ -z "$id" ]; then
      gh api -X POST "repos/$owner/$repo/rulesets" --input - <<<"$want" >/dev/null
      echo "created $name"
      continue
    fi
    shape "$want" <<<"$want" >"$tmp/script.json"
    gh api "repos/$owner/$repo/rulesets/$id" | shape "$want" >"$tmp/repo.json"
    if diff -q "$tmp/repo.json" "$tmp/script.json" >/dev/null; then
      echo "$name is up to date"
      continue
    fi
    echo "$name differs from the script's (- the repo's, + the script's):"
    diff -u "$tmp/repo.json" "$tmp/script.json" | sed 1,2d || true
    if [ "$update" != true ]; then
      echo "Left as it is. Run with --update to replace it."
      continue
    fi
    if [ "$check_given" != true ] && [ "$(checks_of <"$tmp/repo.json")" != "$(checks_of <"$tmp/script.json")" ]; then
      echo "Not replaced: it would change the required check. Run again with --check <the repo's CI check name>." >&2
      status=1
      continue
    fi
    read -r -p "Replace $name in $repo with the script's? [y/N] " answer || true
    if [ "$answer" = y ]; then
      gh api -X PUT "repos/$owner/$repo/rulesets/$id" --input - <<<"$want" >/dev/null
      echo "replaced $name"
    else
      echo "Left as it is."
    fi
  done
  echo "rules on main: $(gh api "repos/$owner/$repo/rules/branches/main" \
    --jq '[.[] | .type + (if .parameters.required_approving_review_count != null then "(approvals=\(.parameters.required_approving_review_count))" else "" end)] | join(", ")')"
done

cat <<'EOF'

Check in each repo's Settings > Rules > Rulesets > main-review that the bypass list
shows "Repository admin". Actor 5 is the admin role in exported rulesets, but
GitHub's API reference doesn't list role IDs. Fix it in the page if it differs.
EOF
exit "$status"
