#!/usr/bin/env bash
# Run this yourself, with your own AWS admin profile and signed in to gh as
# your own GitHub user, never as an agent. It deploys the factory-github-roles
# stack from apps.json, then sets each app repo's AWS_ACCOUNT_ID and AWS_REGION
# variables, which its workflows build the role ARNs from. Run it again after
# adding an app to apps.json; it's idempotent.
#
# It runs only from a clean checkout of the factory's main branch, so it never
# deploys unreviewed roles. It checks each repo ID in apps.json against GitHub,
# so a typo can't leave a role trusting the wrong repo. Before anything changes, it
# shows the IAM changes and asks you to confirm them.
#
# The template goes to CloudFormation straight from this checkout, not through
# the CDK bootstrap's S3 bucket as cdk deploy would send it: agents can write
# to that bucket, so they could swap the template between upload and deploy.
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
region="$(config c.region)"
owner="$(config c.owner.name)"
# The account comes from the profile, not from apps.json, so this public repo
# names no real account. Confirm it before anything changes.
account="$(aws sts get-caller-identity --profile "$profile" --query Account --output text)"
read -r -p "Deploy the factory's GitHub roles to account $account ($profile)? [y/N] " answer
[ "$answer" = "y" ] || { echo "Stopped; nothing changed." >&2; exit 1; }

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
stack=factory-github-roles
template=cdk.out/GitHubRoles.template.json
rm -rf cdk.out
npx cdk synth --quiet -c account="$account" >/dev/null
[ "$(node -p "require('./cdk.out/manifest.json').artifacts.GitHubRoles.properties.stackName")" = "$stack" ] ||
  { echo "The synthesized stack isn't named $stack" >&2; exit 1; }
cfn() { aws cloudformation "$@" --profile "$profile" --region "$region"; }

# The IAM changes, readably. --no-change-set compares templates only, so
# nothing is uploaded.
npx cdk diff --no-change-set --profile "$profile" -c account="$account" || true

if cfn describe-stacks --stack-name "$stack" >/dev/null 2>&1; then type=UPDATE; else type=CREATE; fi
changes="deploy-roles-$(date +%Y%m%d%H%M%S)"
cfn create-change-set --stack-name "$stack" --change-set-name "$changes" --change-set-type "$type" \
  --template-body "file://$template" --capabilities CAPABILITY_NAMED_IAM >/dev/null
if ! cfn wait change-set-create-complete --stack-name "$stack" --change-set-name "$changes" 2>/dev/null; then
  reason="$(cfn describe-change-set --stack-name "$stack" --change-set-name "$changes" --query StatusReason --output text)"
  cfn delete-change-set --stack-name "$stack" --change-set-name "$changes"
  case "$reason" in
    *"didn't contain changes"*|*"No updates are to be performed"*) echo "$stack is already up to date." ;;
    *) echo "CloudFormation couldn't prepare the change: $reason" >&2; exit 1 ;;
  esac
else
  echo "CloudFormation's change set for $stack ($type):"
  cfn describe-change-set --stack-name "$stack" --change-set-name "$changes" \
    --query 'Changes[].ResourceChange.[Action, LogicalResourceId, ResourceType, Replacement]' --output table
  read -r -p "Apply these changes to $stack? [y/N] " answer
  if [ "$answer" != "y" ]; then
    cfn delete-change-set --stack-name "$stack" --change-set-name "$changes"
    echo "Stopped; nothing changed." >&2; exit 1
  fi
  cfn execute-change-set --stack-name "$stack" --change-set-name "$changes"
  if [ "$type" = CREATE ]; then cfn wait stack-create-complete --stack-name "$stack"; else cfn wait stack-update-complete --stack-name "$stack"; fi
  echo "Deployed $stack."
fi
# The stack asks for termination protection, which a change set doesn't apply.
cfn update-termination-protection --enable-termination-protection --stack-name "$stack" >/dev/null

while read -r repo _; do
  echo "== $owner/$repo"
  gh variable set AWS_ACCOUNT_ID --repo "$owner/$repo" --body "$account"
  gh variable set AWS_REGION --repo "$owner/$repo" --body "$region"
done <<<"$apps"
