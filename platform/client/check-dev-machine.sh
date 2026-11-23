#!/usr/bin/env bash
# Check this computer against openspec/specs/dev-machine. Read-only.
# Meant to run from inside a Claude Code session, so it sees what an agent's
# sandboxed commands see. Run outside the sandbox, the sandbox checks fail.
#
# Usage: scripts/check-dev-machine.sh
# Prints one line per check: ok, FAIL, or skip (can't tell yet, with why).
# Exits 1 if any check fails.
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
fails=0
ok()   { printf 'ok    %s\n' "$1"; }
fail() { printf 'FAIL  %s\n' "$1"; fails=$((fails + 1)); }
skip() { printf 'skip  %s\n' "$1"; }
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then ok "$name"; else fail "$name"; fi; }

echo "== Tools"
for c in git gh node npm npx openspec aws claude bwrap socat; do
  if command -v "$c" >/dev/null; then ok "$c on PATH"; else fail "$c on PATH"; fi
done
if command -v node >/dev/null; then
  check "node is 22.12 or later (OpenSpec needs it)" node -e '
    const [a,b]=process.versions.node.split(".").map(Number); process.exit(a>22||(a==22&&b>=12)?0:1)'
fi
command -v npm >/dev/null && check "npm installs global packages into ~/.local" test "$(npm config get prefix)" = "$HOME/.local"

echo "== Skills"
n=0
for l in "$HOME"/.claude/skills/*; do
  [[ -L $l ]] || continue
  if [[ -f $l/SKILL.md ]]; then n=$((n + 1)); else fail "skill link $(basename "$l") resolves"; fi
done
for s in factory-orchestrator factory-repo-setup dev-machine-setup; do
  check "skill $s installed" test -f "$HOME/.claude/skills/$s/SKILL.md"
done
ok "$n linked skills resolve"

echo "== Claude Code settings"
settings=$HOME/.claude/settings.json
if node -e 'JSON.parse(require("fs").readFileSync(process.argv[1]))' "$settings" 2>/dev/null; then
  ok "settings.json is valid JSON"
  get() { node -e 'let v=JSON.parse(require("fs").readFileSync(process.argv[1]));for(const k of process.argv[2].split("."))v=v?.[k];console.log(JSON.stringify(v))' "$settings" "$1"; }
  check "sandbox is enabled" test "$(get sandbox.enabled)" = true
  check "Claude Code refuses to start without the sandbox" test "$(get sandbox.failIfUnavailable)" = true
  check "commands can't run outside the sandbox" test "$(get sandbox.allowUnsandboxedCommands)" = false
  check "bypass permissions mode is disabled" test "$(get permissions.disableBypassPermissionsMode)" = '"disable"'
  # The settings this repo would write, compared as JSON. Differences aren't
  # always wrong (you may have added hooks), so this only reports them.
  if node -e 'const fs=require("fs");const a=JSON.parse(fs.readFileSync(process.argv[1]));const b=JSON.parse(process.argv[2]);process.exit(JSON.stringify(a)===JSON.stringify(b)?0:1)' \
      "$settings" "$(node "$repo/scripts/render-claude-settings.mjs")"; then
    ok "settings.json matches what setup-dev-machine.sh writes"
  else skip "settings.json differs from what setup-dev-machine.sh writes; compare with: node scripts/render-claude-settings.mjs"; fi
else
  fail "settings.json is valid JSON"
fi

echo "== Sandbox"
# Writing outside the allowed folders must fail. If it succeeds, this isn't sandboxed.
probe=$HOME/.dev-machine-sandbox-probe
if (: > "$probe") 2>/dev/null; then rm -f "$probe"; fail "commands run in the sandbox (could write to the home folder)"
else ok "commands run in the sandbox"; fi
token=$HOME/.aws/sso/cache/$(printf admin | sha1sum | cut -c1-40).json
if head -c1 "$token" >/dev/null 2>&1; then fail "admin AWS token is unreadable"
elif [[ -e $token ]]; then ok "admin AWS token is unreadable (it exists)"; else ok "admin AWS token is unreadable (not signed in)"; fi
# A blocked file reads as empty (the sandbox mounts an empty device over it) or can't be opened.
for k in "$HOME"/.ssh/*; do
  n=$(basename "$k")
  [[ $n != *.pub && ( $n == id_* || $(head -c 40 "$k" 2>/dev/null) == *"PRIVATE KEY"* ) ]] || continue
  if [[ -n $(head -c1 "$k" 2>/dev/null) ]]; then fail "SSH key $n is unreadable"; else ok "SSH key $n is unreadable"; fi
done
check "SSH_AUTH_SOCK isn't passed to commands" test -z "${SSH_AUTH_SOCK:-}"
found=0
for s in /tmp/ssh-*/agent.* /run/user/"$(id -u)"/keyring/ssh /run/user/"$(id -u)"/gcr/ssh; do
  [[ -S $s ]] || continue; found=1
  # ssh-add exits 0 (keys listed) or 1 (no keys) if it reached the agent, 2 if it couldn't connect.
  SSH_AUTH_SOCK=$s ssh-add -l >/dev/null 2>&1; rc=$?
  if ((rc == 2)); then ok "SSH agent socket $s refuses connections"; else fail "SSH agent socket $s refuses connections"; fi
done
((found)) || ok "no SSH agent socket found"

echo "== npm"
check "npm can write its cache (~/.npm)" bash -c 't=$HOME/.npm/.dev-machine-probe; : > "$t" && rm -f "$t"'

echo "== AWS"
check "AWS CLI uses the agent config" test "${AWS_CONFIG_FILE:-}" = "$HOME/.aws/agent-config"
check "AWS CLI uses the agent-builder profile" test "${AWS_PROFILE:-}" = agent-builder
if command -v aws >/dev/null; then
  profiles=$(aws configure list-profiles 2>/dev/null | sort | tr '\n' ' ')
  check "only the agent profiles are visible ($profiles)" test "$profiles" = "agent-builder agent-viewonly "
  if arn=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
    role=$(sed -E 's#.*/AWSReservedSSO_([^_]+)_.*#\1#' <<<"$arn")
    case $role in
      Agent-*) ok "signed in to AWS with an agent role ($role)";;
      *) fail "signed in to AWS with an agent role (got $role)";;
    esac
  else skip "AWS sign-in (not signed in; see RUNBOOK.md)"; fi
fi

echo "== GitHub"
# Agents must not reach GitHub with the developer's own credentials.
if timeout 20 git ls-remote git@github.com:cli/cli.git HEAD >/dev/null 2>&1; then
  fail "git over SSH can't use your key"
else ok "git over SSH can't use your key"; fi
if [[ -n ${GH_TOKEN:-} ]]; then skip "agent GitHub identity (GH_TOKEN is set; not checked yet)"
else skip "agent GitHub identity (not set up yet: the GitHub App step isn't built)"; fi

echo
if ((fails)); then echo "$fails check(s) failed."; exit 1; fi
echo "All checks passed."
