#!/usr/bin/env bash
# Run this yourself, signed in to gh as your own GitHub user (not the agents'
# app). The GitHub side of a new factory-built app, in one command:
#
#   1. Creates the repo, public, so the merge door works on GitHub's free plan
#      (rulesets don't apply to private repos there). Skipped if it exists.
#   2. Adds it to the agents' GitHub App installation, so agents can push
#      branches and open pull requests there.
#   3. Adds it to the agents' token config, ~/.config/agent-github/config.json,
#      under the folder you name (default ~/Code), so sessions started there
#      get a token for it. Takes effect in the next session.
#   4. Gives it the factory's rulesets (repo-rulesets.sh): a pull request with
#      a passing "test / test" check, and your approval as code owner.
#
# Then an agent sets the repo up from the factory's template and adds it to
# platform/github-oidc/apps.json; after that merges, platform/github-oidc/
# deploy-roles.sh creates its AWS roles. Safe to re-run.
#
#   platform/github/new-app.sh <repo> ["<description>"] [<agents' folder>]
set -euo pipefail
cd "$(dirname "$0")"

owner=ErikBean
repo=${1:?usage: $0 <repo> [description] [agents folder]}
description=${2:-"A web app built by the factory"}
folder=${3:-$HOME/Code}
config="$HOME/.config/agent-github/config.json"
[[ "$repo" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Not a repo name: $repo" >&2; exit 2; }
# env runs the gh program from PATH, not this function, without the agents' token.
gh() { env -u GH_TOKEN -u GITHUB_TOKEN gh "$@"; }

login="$(gh api user --jq .login)" || { echo "gh isn't signed in as you: run gh auth login" >&2; exit 1; }
echo "Signed in as: $login"

echo "== 1. Repo"
if gh api "repos/$owner/$repo" --jq .full_name >/dev/null 2>&1; then
  [ "$(gh api "repos/$owner/$repo" --jq .visibility)" = public ] \
    || { echo "$owner/$repo exists but isn't public: rulesets need it public on the free plan" >&2; exit 1; }
  echo "$owner/$repo already exists"
else
  gh repo create "$owner/$repo" --public --description "$description" --add-readme >/dev/null
  echo "Created $owner/$repo"
fi
repo_id="$(gh api "repos/$owner/$repo" --jq .id)"

echo "== 2. Agents' app installation"
installation="$(node -p "require('$config').installationId")"
if gh api -X PUT "user/installations/$installation/repositories/$repo_id" >/dev/null; then
  echo "Added to installation $installation"
else
  echo "Couldn't add it through the API. Add $repo under Repository access at" >&2
  echo "https://github.com/settings/installations/$installation, then run this again." >&2
  exit 1
fi

echo "== 3. Agents' token config"
node - "$config" "$folder" "$repo" <<'JS'
const fs = require("fs");
const [file, folder, repo] = process.argv.slice(2);
const c = JSON.parse(fs.readFileSync(file, "utf8"));
c.workspaces ??= {};
const list = (c.workspaces[folder] ??= []);
if (list.includes(repo)) console.log(`${repo} already in ${folder}'s list`);
else { list.push(repo); fs.writeFileSync(file, JSON.stringify(c, null, 2) + "\n"); console.log(`Added ${repo} to ${folder}'s list`); }
JS

echo "== 4. Rulesets"
./repo-rulesets.sh "$repo"

cat <<EOF2

Done. $owner/$repo has ID $repo_id. Next:
- Start a new agent session in $folder (its token now covers $repo), and ask it
  to set $repo up from the factory's template and add it to apps.json.
- After that apps.json change merges: platform/github-oidc/deploy-roles.sh <admin-profile>
EOF2
