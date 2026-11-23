---
name: dev-machine-setup
description: Walks a person through setting up or repairing a computer for AI coding agents, following the factory's platform/client/RUNBOOK.md, and checks the result with platform/client/check-dev-machine.sh. Covers installing Node.js, OpenSpec and the AWS CLI, linking the factory skills from its latest release, the agent's AWS sign-in, the agents' GitHub App token hook, and Claude Code's sandbox settings. Use when the person asks to set up a new dev machine, check this machine, or fix a failing machine check, or when a factory or AWS command fails because a tool, skill, sign-in or sandbox setting is missing.
---

# Dev machine setup

You help a person set up their computer so coding agents can work on it safely, then check it. The steps and their order are in the factory's `platform/client/RUNBOOK.md`; the requirements are in `openspec/specs/agent-client/spec.md`. Read both before you start.

Find the factory from this skill's folder: resolve the symlinks, and the factory is two levels up from the skill folder. That checkout is the one the setup keeps at the latest release, so read from it, and give the person commands for their own checkout, such as `~/Code/factory`.

## What you can and can't do

You're running inside Claude Code's sandbox, or you will be once setup is done. That means:

- **The person runs the setup script.** `platform/client/setup-dev-machine.sh` installs into the home folder and writes `~/.claude/settings.json`, and sandboxed commands can do neither. Give them the command to run in their own terminal. Don't try to work around the sandbox, and don't ask them to turn it off.
- **The person does every sign-in.** AWS and GitHub sign-ins happen in a browser. Give the exact command from the runbook, and say which user to sign in as.
- **You can't edit your own settings.** If `~/.claude/settings.json` needs a change, show the person the change. Prefer re-running the setup script, which writes a `.proposed` copy to compare.
- **You run the check.** `platform/client/check-dev-machine.sh` is read-only and is meant to run from inside the sandbox.

## How to run it

1. Run `platform/client/check-dev-machine.sh` first, even on a new machine. Its failures tell you which runbook steps are left. If Claude Code isn't running in the sandbox yet, the sandbox checks fail; that's expected before step 4.
2. Take the person through the runbook steps that are left, one at a time. For each one, say what it does and what they should see, then wait for them to report back.
3. Re-run the check after each step that should change it. Finish when every line is `ok` or an expected `skip`.

## Known failures and their causes

- **`ForbiddenException ... GetRoleCredentials ... No access`** on an AWS command: the browser approved the sign-in as a user who doesn't hold that role. Usually the person approved the agent's sign-in as themselves, because the browser reused their portal session. Have them log that session out and sign in again from a private window. If it happens on the admin profile, check that their own user holds the admin permission set.
- **`The config profile (admin) could not be found`:** the admin profile was created with `aws configure sso`, which names it after the role and account. The setup script writes it as `admin`; re-run its `aws` step.
- **`settings.json differs`:** the person has changes the script doesn't make, such as plugins or other settings. That's a `skip`, not a failure. Compare with `node platform/client/render-claude-settings.mjs` and say what differs.
- **`skills come from a factory release` fails:** the skill links lead somewhere else, such as an old factory-skills checkout. Have the person run `platform/client/setup-dev-machine.sh skills`, which moves the links.
- **`gh` says it needs authentication, or `git push` is refused:** the person's own GitHub credentials are blocked, which is the sandbox working. Agents get their own token from the agents' GitHub App through `~/.claude/hooks/agent-github-token.mjs`; if `GH_TOKEN` isn't set, check runbook step 7 and `platform/client/README.md`.
- **`EROFS` or "read-only file system" from npm:** `~/.npm` isn't writable in the sandbox. The settings should have `sandbox.filesystem.allowWrite` with `~/.npm`.

## Privacy

The person's config is in `config.local/machine.env` at the factory's root, which is gitignored. Never copy real account IDs, URLs, user names or command output into files in the repo; see the factory's `AGENTS.md`.
