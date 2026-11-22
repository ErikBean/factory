#!/usr/bin/env bash
# Creates a demo app from template/ with scripts/create-app.mjs, then runs what
# an app's CI runs. The app installs the library from this checkout's own
# pack, so a version that isn't published yet still tests. CI runs this.
set -euo pipefail
factory="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
app="$work/demo-app"
git init -q "$app"

fail() { echo "FAIL: $*" >&2; exit 1; }

skills=--skip-skills
[ -d "$factory/skills/factory-orchestrator" ] && skills=
node "$factory/scripts/create-app.mjs" "$app" demo-app $skills

version="$(node -p "require('$factory/cdk/package.json').version")"
! grep -rnE '\{\{[a-z_]+\}\}' "$app" --exclude-dir=.git >/dev/null || fail "placeholders left: $(grep -rlnE '\{\{[a-z_]+\}\}' "$app" --exclude-dir=.git)"
grep -q "app-ci.yml@v$version" "$app/.github/workflows/ci.yml" || fail "ci.yml doesn't pin v$version"
grep -q '"@favabean/factory-cdk": "^'"$version"'"' "$app/package.json" || fail "package.json doesn't depend on ^$version"
grep -q 'new FactoryStack(app, "DemoAppStack", { project: "demo-app" })' "$app/lib/app.ts" || fail "lib/app.ts names"
[ -x "$app/scripts/sync-factory-skills.sh" ] || fail "sync script lost its executable bit"
[ -x "$app/.claude/hooks/block-merge.mjs" ] || fail "merge hook lost its executable bit"
if [ -z "$skills" ]; then
  [ -f "$app/.agents/skills/factory-orchestrator/SKILL.md" ] || fail "skills not synced"
fi

(cd "$factory" && npm pack --workspace cdk --pack-destination "$work" --silent >/dev/null)
cd "$app"
npm install --ignore-scripts --no-audit --no-fund --silent "$work"/favabean-factory-cdk-"$version".tgz
npm install --no-audit --no-fund --silent
npm test --silent
npx cdk synth --quiet -c stage=prod
npx --no-install factory-check-boundaries cdk.out
[ "$(node -p "require('./cdk.out/manifest.json').artifacts.DemoAppStack.properties.stackName")" = demo-app ] || fail "prod stack name"
echo "ok: demo-app created from template/ at v$version, tested and synthesized"
