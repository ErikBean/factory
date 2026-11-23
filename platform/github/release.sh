#!/usr/bin/env bash
# Run this yourself, signed in to gh as your own GitHub user (not the agents'
# app), from a clean checkout of the factory's main after the version bump has
# merged. It does the admin's part of a release (see RELEASING.md):
#
#   1. Checks main is clean and up to date with GitHub, that CI passed on it,
#      that CHANGELOG.md has the version's section, and that neither the tag
#      nor the npm version exists yet.
#   2. Creates the release v<version> from cdk/package.json, at main's full
#      commit SHA, with the changelog section as its notes, after you confirm.
#   3. Waits for publish.yml to stage the package on npm, and prints its stage
#      ID and what to check.
#   4. Offers to run `npm stage approve` for you (your npm 2FA), again while
#      npm's automated review is still running, then waits until the version
#      is live.
#
# A release can't be moved or deleted once created, so it stops at the first
# problem, before anything changes. Safe to re-run: it picks up a release that
# already exists at main's commit and goes on from step 3.
#
#   platform/github/release.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

# env runs the gh program from PATH, not this function, without the agents' token.
gh() { env -u GH_TOKEN -u GITHUB_TOKEN gh "$@"; }
say() { printf '\n== %s\n' "$*"; }
stop() { echo "Stopped: $*" >&2; exit 1; }

repo="$(node -p "require('./platform/github-oidc/apps.json').factoryRepo")"
package="$(node -p "require('./cdk/package.json').name")"
version="$(node -p "require('./cdk/package.json').version")"
tag="v$version"
login="$(gh api user --jq .login)" || stop "gh isn't signed in as you: run gh auth login"
echo "Signed in to GitHub as $login. Releasing $repo $tag ($package@$version)."

say "1. Checks"
[ "$(git branch --show-current)" = main ] || stop "check out main first"
[ -z "$(git status --porcelain --untracked-files=no)" ] || stop "main has local changes"
git fetch -q "https://github.com/$repo.git" main
sha="$(git rev-parse HEAD)"
[ "$sha" = "$(git rev-parse FETCH_HEAD)" ] || stop "local main isn't GitHub's main: git pull first"
ci="$(gh api "repos/$repo/commits/$sha/check-runs" --jq '[.check_runs[] | select(.name == "test")][0].conclusion // "none"')"
[ "$ci" = success ] || stop "CI's test check on $sha is '$ci', not success"
if npm view "$package@$version" version >/dev/null 2>&1; then stop "$package@$version is already on npm: bump the version in a PR"; fi
# The version's CHANGELOG.md section, from its heading to the next version's.
notes="$(awk -v h="## [$version]" 'index($0, h) == 1 {on = 1; next} /^## \[|^\[[0-9]/ {on = 0} on' CHANGELOG.md)"
[ -n "$(printf '%s' "$notes" | tr -d '[:space:]')" ] || stop "CHANGELOG.md has no '## [$version]' section: add it in the version-bump PR"
# On a 404, gh api prints the error body to stdout, so trust its output only when it succeeds.
existing=""
if out="$(gh api "repos/$repo/git/ref/tags/$tag" --jq .object.sha 2>/dev/null)"; then existing="$out"; fi
if [ -n "$existing" ] && [ "$existing" != "$sha" ]; then stop "$tag already exists at another commit: bump the version in a PR"; fi
echo "main is $sha, clean, CI passed, CHANGELOG.md has $version, and $tag is free or already at this commit."

say "2. Release"
prerelease=()
case "$version" in *-*) prerelease=(--prerelease) ;; esac
if [ -n "$existing" ]; then
  echo "$tag already exists at this commit; going on to the publish run."
else
  previous="$(gh release list --repo "$repo" --limit 1 --json tagName --jq '.[0].tagName // "none"')"
  echo "Previous release: $previous. Changes since:"
  if [ "$previous" != none ]; then git log --oneline "$previous..$sha" | sed 's/^/  /'; fi
  read -r -p "Create $tag at $sha? It can't be moved or deleted afterwards. [y/N] " answer
  [ "$answer" = y ] || stop "nothing created"
  notes_file="$(mktemp)"
  printf '%s\n' "$notes" > "$notes_file"
  gh release create "$tag" --repo "$repo" --target "$sha" --title "$tag" --notes-file "$notes_file" "${prerelease[@]}" >/dev/null
  rm -f "$notes_file"
  echo "Created $tag."
fi

say "3. Publish run"
run=""
for _ in $(seq 1 60); do
  run="$(gh run list --repo "$repo" --workflow publish.yml --event release --limit 10 \
    --json databaseId,headSha --jq "[.[] | select(.headSha == \"$sha\")][0].databaseId // empty")"
  [ -n "$run" ] && break
  sleep 5
done
[ -n "$run" ] || stop "no publish run started for $tag after 5 minutes: check https://github.com/$repo/actions"
echo "Waiting for https://github.com/$repo/actions/runs/$run"
gh run watch "$run" --repo "$repo" --exit-status >/dev/null || stop "the publish run failed: https://github.com/$repo/actions/runs/$run"
stage="$(gh run view "$run" --repo "$repo" --log | grep -oE 'staged with id [0-9a-f-]+' | head -1 | awk '{print $4}')"
[ -n "$stage" ] || stop "the run passed but no stage ID was found in its log: check it by hand"
echo "Staged $package@$version with ID $stage."
echo "Before approving, check: npm stage view $stage"
echo "  (the version, the files: dist/, LICENSE, package.json, and provenance from this run)"

say "4. Approve"
npm whoami >/dev/null 2>&1 || { echo "npm needs you signed in to approve:"; npm login; }
read -r -p "Run 'npm stage approve $stage' now? [y/N] " answer
[ "$answer" = y ] || { echo "Approve later with: npm stage approve $stage"; exit 0; }
# Approval fails with a 409 until npm's automated review of the package has
# finished, which can take a few minutes after staging. Each try asks for 2FA,
# so wait for the human rather than retrying on a timer.
until npm stage approve "$stage"; do
  echo "Approval failed. If npm says automated review hasn't finished, wait a few minutes."
  read -r -p "Try again? [Y/n] " answer
  [ "$answer" != n ] || { echo "Approve later with: npm stage approve $stage"; exit 0; }
done
for _ in $(seq 1 36); do
  [ "$(npm view "$package" dist-tags.latest 2>/dev/null)" = "$version" ] && break
  [ "${prerelease[*]:-}" ] && [ "$(npm view "$package" dist-tags.next 2>/dev/null)" = "$version" ] && break
  sleep 10
done
live="$(npm view "$package@$version" version 2>/dev/null || true)"
[ "$live" = "$version" ] || stop "$package@$version isn't live after 6 minutes: check npm stage list $package"
echo "$package@$version is live. Consider 'npm logout' now, so no npm token stays on this machine."
echo "Next: ask an agent to move the apps to $tag (RELEASING.md, step 7)."
