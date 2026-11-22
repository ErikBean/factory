#!/usr/bin/env bash
# Lints the factory-repo-setup templates and the factory's workflows, and runs
# the skills' tests. The factory's CI runs this on every pull request. Needs
# node, shellcheck, actionlint and cfn-lint on the PATH;
# skills/tests/requirements.txt pins the last three. Runs from the repo root.
set -euo pipefail
cd "$(dirname "$0")/.."

templates=skills/factory-repo-setup/templates

echo "shellcheck"
shellcheck "$templates"/*.sh skills/check.sh skills/tests/*.sh

echo "node --check"
for f in "$templates"/*.mjs "$templates"/claude/hooks/*.mjs; do node --check "$f"; done

echo "cfn-lint"
cfn-lint "$templates"/*.yaml

echo "actionlint"
actionlint .github/workflows/*.yml
# The deploy template calls ci.yml by its path in a set-up repo, so lint the
# templates laid out the same way.
project="$(mktemp -d)"
trap 'rm -rf "$project"' EXIT
git init -q "$project"
mkdir -p "$project/.github/workflows"
cp "$templates"/workflows/*.yml "$project/.github/workflows/"
(cd "$project" && actionlint .github/workflows/*.yml)

for t in skills/tests/*.test.sh; do
  echo "$t"
  "$t"
done
