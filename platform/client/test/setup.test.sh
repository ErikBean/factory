#!/usr/bin/env bash
# Tests setup-dev-machine.sh's skills, aws and claude steps in a throwaway home
# folder, with placeholder config. The tools step downloads, so it isn't tested here.
# Usage: platform/client/test/setup.test.sh
# Each expectation is a single-quoted string that expect() evals, so the
# expansions in it and the variables it reads are deliberate.
# shellcheck disable=SC2016,SC2034
set -euo pipefail
client=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME=$t/home; mkdir -p "$HOME/.ssh"
pass=0; failed=0
expect() { if eval "$2"; then pass=$((pass+1)); else echo "FAIL: $1"; failed=$((failed+1)); fi; }

# A local stand-in for the factory, with two skills released as v0.1.0, and
# an unreleased change on main after it.
src=$t/factory-src
mkdir -p "$src/skills/factory-a" "$src/skills/factory-b"
echo a > "$src/skills/factory-a/SKILL.md"; echo b > "$src/skills/factory-b/SKILL.md"
g() { git -C "$src" -c user.name=t -c user.email=t@example.com "$@"; }
g init -q && g add -A && g commit -qm init && g tag v0.1.0
echo unreleased > "$src/skills/factory-a/SKILL.md"; g commit -qam unreleased

printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nx\n' > "$HOME/.ssh/id_test"
printf 'ssh-ed25519 AAAA test\n' > "$HOME/.ssh/id_test.pub"
printf -- '-----BEGIN RSA PRIVATE KEY-----\nx\n' > "$HOME/.ssh/work_key"

sed -e "s|^FACTORY_REPO=.*|FACTORY_REPO=$src|" \
    -e "s|^FACTORY_DIR=.*|FACTORY_DIR=$t/factory|" \
    "$client/machine.env.example" > "$t/machine.env"
export DEV_MACHINE_CONFIG=$t/machine.env
run() { "$client/setup-dev-machine.sh" skills aws claude; }

# A link left by an older setup, into a factory-skills checkout.
mkdir -p "$HOME/.agents/skills" "$t/factory-skills/skills/factory-a"
ln -s "$t/factory-skills/skills/factory-a" "$HOME/.agents/skills/factory-a"

out=$(run)
expect "skills are linked through ~/.agents/skills" '[[ -f $HOME/.claude/skills/factory-a/SKILL.md && $(readlink "$HOME/.claude/skills/factory-a") == ../../.agents/skills/factory-a ]]'
expect "skills come from the latest release, not main" '[[ $(cat "$HOME/.claude/skills/factory-a/SKILL.md") == a && $(git -C "$t/factory" describe --tags --exact-match) == v0.1.0 ]]'
expect "an old link is moved to the factory" '[[ $(readlink "$HOME/.agents/skills/factory-a") == "$t/factory/skills/factory-a" ]] && grep -q "relinked" <<<"$out"'
expect "the agent-github-token hook is installed" '[[ -x $HOME/.claude/hooks/agent-github-token.mjs ]] && cmp -s "$HOME/.claude/hooks/agent-github-token.mjs" "$client/agent-github-token.mjs"'
expect "admin profile written" 'grep -q "^\[profile admin\]" "$HOME/.aws/config"'
expect "agent config has both agent profiles" '[[ $(grep -c "^\[profile agent-" "$HOME/.aws/agent-config") == 2 ]]'
expect "agent config is private" '[[ $(stat -c %a "$HOME/.aws/agent-config") == 600 ]]'
s=$HOME/.claude/settings.json
q() { node -e 'let v=JSON.parse(require("fs").readFileSync(process.argv[1]));console.log(JSON.stringify(eval("v"+process.argv[2])))' "$s" "$1"; }
expect "settings: sandbox on" '[[ $(q .sandbox.enabled) == true ]]'
expect "settings: agent profile" '[[ $(q .env.AWS_PROFILE) == "\"agent-builder\"" ]]'
expect "settings: admin token denied by its SHA-1 name" 'q .sandbox.credentials.files | grep -q d033e22ae348aeb5660fc2140aec35850c4da997.json'
expect "settings: SSH keys denied, by name and by header" 'q .sandbox.credentials.files | grep -q "~/.ssh/id_test\"" && q .sandbox.credentials.files | grep -q "~/.ssh/work_key\""'
expect "settings: public keys not denied" '! q .sandbox.credentials.files | grep -q id_test.pub'
expect "settings: the hook runs at session start and before Bash" '[[ $(q .hooks.SessionStart[0].hooks[0].command) == "\"$HOME/.claude/hooks/agent-github-token.mjs session-start\"" && $(q .hooks.PreToolUse[0].matcher) == "\"Bash\"" ]]'

# claude-settings.example.json is the renderer's output with placeholders.
e=$t/example-home/YOUR_USER; mkdir -p "$e/.ssh"; printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nx\n' > "$e/.ssh/YOUR_SSH_KEY"
norm() { node -e 'const s=(o)=>Array.isArray(o)?o.map(s):o&&typeof o=="object"?Object.fromEntries(Object.keys(o).sort().map(k=>[k,s(o[k])])):o;console.log(JSON.stringify(s(JSON.parse(require("fs").readFileSync(0,"utf8")))))'; }
expect "the example settings match the renderer" '[[ $(HOME=$e node "$client/render-claude-settings.mjs" | sed "s#$t/example-home#/home#g" | norm) == "$(norm < "$client/claude-settings.example.json")" ]]'

# Re-running changes nothing: every path, link target and file content stays the same.
snapshot() { (cd "$HOME" && find . | sort | while read -r f; do
  echo "$f"; if [[ -L $f ]]; then readlink "$f"; elif [[ -f $f ]]; then cat "$f"; fi; done) | sha1sum; }
before=$(snapshot)
out=$(run)
after=$(snapshot)
expect "re-running changes nothing" '[[ $before == "$after" ]]'
expect "re-running reports everything ok" '! grep -qE "^(wrote|linked|differs)" <<<"$out"'

# A settings file that differs is left alone; a proposed copy goes next to it.
echo '{"theme":"dark"}' > "$s"
out=$(run)
expect "differing settings left alone" '[[ $(cat "$s") == "{\"theme\":\"dark\"}" ]]'
expect "proposed settings written alongside" '[[ -f $s.proposed ]] && grep -q "Compare .*settings.json" <<<"$out"'

# A skill path taken by something else is reported, not replaced.
rm "$HOME/.claude/skills/factory-b"; mkdir "$HOME/.claude/skills/factory-b"
out=$(run)
expect "existing folder at a skill path is left alone" '[[ -d $HOME/.claude/skills/factory-b && ! -L $HOME/.claude/skills/factory-b ]] && grep -q "factory-b exists" <<<"$out"'

echo "$pass passed, $failed failed"
((failed == 0))
