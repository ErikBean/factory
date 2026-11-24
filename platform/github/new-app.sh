#!/usr/bin/env bash
# Run this yourself, signed in to gh as your own GitHub user (not the agents'
# app). The GitHub side of a new factory-built app, in one command:
#
#   1. Creates the repo, public by default, so the merge door works on GitHub's
#      free plan (rulesets don't apply to private repos there). With --private,
#      it creates a private repo, after checking your account is on GitHub Pro,
#      where rulesets do apply. Skipped if it exists.
#   2. Has you add it to the agents' GitHub App installation, on the app's
#      settings page, so agents can push branches and open pull requests there.
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
#   platform/github/new-app.sh [--private] <repo> ["<description>"] [<agents' folder>]
set -euo pipefail
cd "$(dirname "$0")"

visibility=public
if [ "${1:-}" = --private ]; then visibility=private; shift; fi
owner=ErikBean
repo=${1:?usage: $0 [--private] <repo> [description] [agents folder]}
description=${2:-"A web app built by the factory"}
folder=${3:-$HOME/Code}
config="$HOME/.config/agent-github/config.json"
[[ "$repo" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Not a repo name: $repo" >&2; exit 2; }
# env runs the gh program from PATH, not this function, without the agents' token.
gh() { env -u GH_TOKEN -u GITHUB_TOKEN gh "$@"; }

login="$(gh api user --jq .login)" || { echo "gh isn't signed in as you: run gh auth login" >&2; exit 1; }
echo "Signed in as: $login"

echo "== 1. Repo"
# Rulesets, the merge door, apply to a private repo only on a paid plan.
if [ "$visibility" = private ]; then
  # GitHub shows the plan only to tokens with the user scope, which gh doesn't
  # ask for by default; step 4 fails if the plan doesn't allow rulesets.
  plan="$(gh api user --jq '.plan.name // "unknown"')"
  [ "$plan" != free ] \
    || { echo "Your account is on GitHub's free plan: rulesets need GitHub Pro for a private repo. Upgrade, or create it public" >&2; exit 1; }
  echo "Plan: $plan"
fi
if gh api "repos/$owner/$repo" --jq .full_name >/dev/null 2>&1; then
  actual="$(gh api "repos/$owner/$repo" --jq .visibility)"
  [ "$actual" = "$visibility" ] \
    || { echo "$owner/$repo exists but is $actual, not $visibility: run with$([ "$actual" = private ] && echo "" || echo "out") --private to match" >&2; exit 1; }
  echo "$owner/$repo already exists ($visibility)"
else
  gh repo create "$owner/$repo" "--$visibility" --description "$description" --add-readme >/dev/null
  echo "Created $owner/$repo ($visibility)"
fi
repo_id="$(gh api "repos/$owner/$repo" --jq .id)"

echo "== 2. Agents' app installation"
# GitHub lets only a token tied to the agents' app change its repo list, not
# your gh sign-in's, so you add the repo on the app's settings page.
installation="$(node -p "require('$config').installationId")"
echo "Add $repo under Repository access at https://github.com/settings/installations/$installation"
echo "(Only select repositories, then Save), unless it's there already."
read -r -p "Is $repo in the agents' app installation? [y/N] " answer
[ "$answer" = y ] || { echo "Stopped: add it there, then run this again." >&2; exit 1; }

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
if ! ./repo-rulesets.sh "$repo"; then
  echo "The rulesets weren't applied, so $owner/$repo has no merge door: don't let agents work in it yet." >&2
  [ "$visibility" = private ] && echo "On a private repo, they need GitHub Pro. Upgrade, then run this again." >&2
  exit 1
fi

cat <<EOF2

Done. $owner/$repo has ID $repo_id. Next:
- Start a new agent session in $folder (its token now covers $repo), and ask it
  to set $repo up from the factory's template and add it to apps.json.
- After that apps.json change merges: platform/github-oidc/deploy-roles.sh <admin-profile>
EOF2
