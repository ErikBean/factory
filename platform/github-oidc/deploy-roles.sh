#!/usr/bin/env bash
# Run this yourself, with your own AWS admin profile and signed in to gh as
# your own GitHub user, never as an agent. It deploys the factory-github-roles
# stack from apps.json, then sets each app repo's AWS_ACCOUNT_ID and AWS_REGION
# variables, which its workflows build the role ARNs from. Run it again after
# adding an app to apps.json; it's idempotent.
#
# It runs only from a clean checkout of the factory's main branch, so it never
# deploys unreviewed roles. It checks each repo ID in apps.json against GitHub,
# so a typo can't leave a role trusting the wrong repo. Before anything changes, cdk deploy
# shows the IAM changes and asks you to confirm them.
#
#   platform/github-oidc/deploy-roles.sh <admin-profile>
set -euo pipefail
cd "$(dirname "$0")"
profile=${1:?usage: $0 <admin-profile>}
# env runs the gh program from PATH, not this function, without the agents' token.
gh() { env -u GH_TOKEN -u GITHUB_TOKEN gh "$@"; }

login="$(gh api user --jq .login)" || { echo "gh isn't signed in as you: run gh auth login" >&2; exit 1; }
echo "GitHub: $login"
config() { node -p "const c = require('./apps.json'); $1"; }
account="$(config c.account)"
region="$(config c.region)"
owner="$(config c.owner.name)"
signed_in="$(aws sts get-caller-identity --profile "$profile" --query Account --output text)"
[ "$signed_in" = "$account" ] || { echo "Profile $profile is account $signed_in, but apps.json says $account" >&2; exit 1; }
echo "AWS: $account ($profile)"

[ "$(gh api "users/$owner" --jq .id)" = "$(config c.owner.id)" ] || { echo "apps.json has the wrong ID for $owner" >&2; exit 1; }
apps="$(config "c.apps.map(a => a.repo + ' ' + a.id).join('\n')")"
while read -r repo id; do
  actual="$(gh api "repos/$owner/$repo" --jq .id)"
  [ "$actual" = "$id" ] || { echo "apps.json has ID $id for $repo, but GitHub says $actual" >&2; exit 1; }
done <<<"$apps"

# Deploy only reviewed code: the checkout must be the factory's main branch as
# it is on GitHub, with no local changes.
factory="$(config c.factoryRepo)"
main="$(gh api "repos/$factory/commits/main" --jq .sha)"
[ "$(git rev-parse HEAD)" = "$main" ] || { echo "Check out $factory's main ($main) first" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "The checkout has local changes" >&2; exit 1; }

# No install scripts: they'd run as you, next to your AWS admin sign-in.
(cd ../.. && npm ci --ignore-scripts)
npx cdk deploy --profile "$profile" --require-approval any-change

while read -r repo _; do
  echo "== $owner/$repo"
  gh variable set AWS_ACCOUNT_ID --repo "$owner/$repo" --body "$account"
  gh variable set AWS_REGION --repo "$owner/$repo" --body "$region"
done <<<"$apps"
