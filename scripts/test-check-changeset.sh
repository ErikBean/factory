#!/usr/bin/env bash
# Runs scripts/check-changeset.mjs against small throwaway repos, one per case:
# a pull request with a note, with none, with a major note before 1.0, with an
# empty note, the version-bump pull request, and Dependabot's.
#
#   scripts/test-check-changeset.sh
set -euo pipefail
check="$(cd "$(dirname "$0")" && pwd)/check-changeset.mjs"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
failed=0

# Each case starts from main: cdk/package.json at 0.3.0 and one pending note.
setup() {
  rm -rf "$work/repo" && mkdir -p "$work/repo/cdk" "$work/repo/.changeset" && cd "$work/repo"
  git init -q -b main
  echo '{"name": "@favabean/factory-cdk", "version": "0.3.0"}' > cdk/package.json
  echo '# Change notes' > .changeset/README.md
  printf -- '---\n"@favabean/factory-cdk": patch\n---\n\nAn earlier fix.\n' > .changeset/earlier.md
  git add -A && git -c user.name=t -c user.email=t@example.com commit -qm main
  git checkout -q -b pr
}
commit() { git add -A && git -c user.name=t -c user.email=t@example.com commit -qm pr; }
expect() { # expect pass|fail <case>, with PR_AUTHOR from the environment
  local want="$1" name="$2" got=pass
  node "$check" main >/dev/null 2>&1 || got=fail
  if [ "$got" = "$want" ]; then echo "ok: $name"; else echo "FAILED: $name (expected $want, got $got)"; failed=1; fi
}

setup; echo change > file; printf -- '---\n"@favabean/factory-cdk": minor\n---\n\nA change.\n\n**Upgrading:** do this.\n' > .changeset/a.md; commit
expect pass "a note"

setup; echo change > file; commit
expect fail "no note"

setup; echo change > file; printf -- '---\n"@favabean/factory-cdk": major\n---\n\nBreaks apps.\n' > .changeset/a.md; commit
expect fail "a major note before 1.0"

setup; echo change > file; printf -- '---\n---\n\nCI only.\n' > .changeset/a.md; commit
expect pass "an empty note"

setup; echo change > file; printf -- '---\n"@favabean/factory-cdk": patch\n---\n\n' > .changeset/a.md; commit
expect fail "a note with no text"

setup; echo change > file; printf -- '---\n"@favabean/other": patch\n---\n\nA change.\n' > .changeset/a.md; commit
expect fail "a note naming another package"

setup; git rm -q .changeset/earlier.md; echo '{"name": "@favabean/factory-cdk", "version": "0.3.1"}' > cdk/package.json; commit
expect pass "the version-bump pull request"

setup; git rm -q .changeset/earlier.md; commit
expect fail "notes deleted without a version bump"

setup; echo change > file; commit
PR_AUTHOR='dependabot[bot]' expect pass "Dependabot's pull request"

exit "$failed"
