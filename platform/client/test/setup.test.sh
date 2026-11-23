#!/usr/bin/env bash
# Tests setup-dev-machine.sh's skills, aws and claude steps in a throwaway home
# folder, with placeholder config. The tools step downloads, so it isn't tested here.
# Usage: bash tests/setup.test.sh
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME=$t/home; mkdir -p "$HOME/.ssh"
pass=0; failed=0
expect() { if eval "$2"; then pass=$((pass+1)); else echo "FAIL: $1"; failed=$((failed+1)); fi; }

# A local stand-in for the factory-skills repo, with two skills.
src=$t/factory-skills-src
mkdir -p "$src/skills/factory-a" "$src/skills/factory-b"
echo a > "$src/skills/factory-a/SKILL.md"; echo b > "$src/skills/factory-b/SKILL.md"
git -C "$src" init -q && git -C "$src" add -A && git -C "$src" -c user.name=t -c user.email=t@example.com commit -qm init

printf -- '-----BEGIN OPENSSH PRIVATE KEY-----\nx\n' > "$HOME/.ssh/id_test"
printf 'ssh-ed25519 AAAA test\n' > "$HOME/.ssh/id_test.pub"
printf -- '-----BEGIN RSA PRIVATE KEY-----\nx\n' > "$HOME/.ssh/work_key"

sed -e "s|^FACTORY_SKILLS_REPO=.*|FACTORY_SKILLS_REPO=$src|" \
    -e "s|^FACTORY_SKILLS_DIR=.*|FACTORY_SKILLS_DIR=$t/factory-skills|" \
    "$repo/config/machine.env.example" > "$t/machine.env"
export DEV_MACHINE_CONFIG=$t/machine.env
run() { "$repo/scripts/setup-dev-machine.sh" skills aws claude; }

out=$(run)
expect "skills are linked through ~/.agents/skills" '[[ $(cat "$HOME/.claude/skills/factory-a/SKILL.md") == a && $(readlink "$HOME/.claude/skills/factory-a") == ../../.agents/skills/factory-a ]]'
expect "the dev-machine-setup skill is linked" '[[ -f $HOME/.claude/skills/dev-machine-setup/SKILL.md ]]'
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
