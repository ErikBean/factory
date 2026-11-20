#!/usr/bin/env bash
# Run this yourself, signed in to gh as your own GitHub user (not the agents'
# app). It protects the factory's release tags, which apps' workflow pins and
# the platform's GitHub OIDC roles trust (platform/github-oidc):
#
#   release-tags-create  only repository admins can create a v* tag. The
#                        agents' app can push branches, but not a tag the roles
#                        would accept.
#   release-tags-locked  nobody, admins included, can move or delete a v* tag.
#                        To undo a bad tag, release a new version.
#
# It also turns on immutable releases, so a published release's tag and
# assets can't change either. Safe to re-run: it skips what's already there.
#
#   platform/github/release-tags.sh [repo]    # default: factory
set -euo pipefail

owner=ErikBean
repo=${1:-factory}
# env runs the gh program from PATH, not this function, without the agents' token.
gh() { env -u GH_TOKEN -u GITHUB_TOKEN gh "$@"; }

login="$(gh api user --jq .login)" || { echo "gh isn't signed in as you: run gh auth login" >&2; exit 1; }
echo "Signed in as: $login"
echo "== $owner/$repo"

existing="$(gh api "repos/$owner/$repo/rulesets" --jq '.[].name')"
add() { # name, ruleset JSON
  if grep -qx "$1" <<<"$existing"; then
    echo "$1 already exists"
  else
    gh api -X POST "repos/$owner/$repo/rulesets" --input - <<<"$2" >/dev/null
    echo "Added $1"
  fi
}

# The Repository admin role's ID is 5, as in the main-review ruleset.
add release-tags-create '{
  "name": "release-tags-create",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "bypass_actors": [{ "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }],
  "rules": [{ "type": "creation" }]
}'

add release-tags-locked '{
  "name": "release-tags-locked",
  "target": "tag",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/tags/v*"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [{ "type": "update" }, { "type": "deletion" }]
}'

gh api -X PUT "repos/$owner/$repo/immutable-releases" >/dev/null
echo "Immutable releases: on"
echo
echo "Check on the repo's Rules page that release-tags-create's bypass list shows Repository admin."
