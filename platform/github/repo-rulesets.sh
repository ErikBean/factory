#!/usr/bin/env bash
# Run this yourself, signed in to gh as your own GitHub user (not the agents' app).
# Gives each repo named on the command line the factory's two rulesets on its
# default branch, the same as the factory and its apps have:
#   main         a pull request and a passing required check, no force
#                pushes, and no bypass for anyone. The check defaults to
#                "test / test", the name a factory-built app's CI reports: its
#                test job calls the factory's app-ci.yml, and GitHub names such
#                checks "<caller job> / <called job>".
#   main-review  a code owner's approval of the latest push. Repository admins
#                may bypass it on their own pull requests, through a pull
#                request only. A GitHub App can't be a code owner, so the agents
#                can't merge their own pull requests.
# Safe to re-run: it skips rulesets a repo already has.
#
#   platform/github/repo-rulesets.sh my-new-app            # requires "test / test"
#   platform/github/repo-rulesets.sh --check test factory  # the factory's own CI job is "test"
set -euo pipefail

owner=ErikBean
check="test / test"
if [ "${1:-}" = "--check" ]; then check=${2:?--check needs a check name}; shift 2; fi
[ $# -gt 0 ] || { echo "Usage: $0 [--check <name>] <repo>..." >&2; exit 2; }
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
        "require_last_push_approval": true,
        "required_review_thread_resolution": false } }
  ]
}'

for repo in "$@"; do
  echo
  echo "== $owner/$repo"
  existing="$(gh api "repos/$owner/$repo/rulesets" --jq '.[].name')"
  for pair in "main:$main_ruleset" "main-review:$review_ruleset"; do
    name="${pair%%:*}"
    if grep -qx "$name" <<<"$existing"; then
      echo "$name already exists"
    else
      gh api -X POST "repos/$owner/$repo/rulesets" --input - <<<"${pair#*:}" >/dev/null
      echo "created $name"
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
