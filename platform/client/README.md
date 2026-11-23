# Client setup

The developer's machine, as the [agent-client spec](../../openspec/specs/agent-client/spec.md) requires: the tools and factory skills agents need, their AWS and GitHub sign-ins, and Claude Code's sandbox.

- [`RUNBOOK.md`](RUNBOOK.md): the steps for a new machine, in order, including the sign-ins only a person can do. The `dev-machine-setup` skill walks a person through it.
- `setup-dev-machine.sh`: you run it, outside Claude Code. It installs what's missing under `~/.local`, links the skills from a checkout of the factory's latest release, writes the AWS profiles, installs the token hook and writes Claude Code's settings. It never overwrites a file that differs: it writes `<file>.proposed` next to it. Re-running it is safe. It reads `config.local/machine.env` at the factory's root; `machine.env.example` lists what goes in it.
- `check-dev-machine.sh`: an agent runs it from inside its sandbox. It checks the spec's scenarios that a machine can check. `test/setup.test.sh` tests the setup in a throwaway home folder.

The files below hold placeholders only.

- `claude-settings.example.json`: what `setup-dev-machine.sh` writes to `~/.claude/settings.json` (it's `render-claude-settings.mjs`'s output, with `YOUR_USER` and `YOUR_SSH_KEY`, one entry per private key in `~/.ssh`). The admin token file's name is the SHA-1 of the SSO session name `admin`, which the setup gives the admin profile.
- `aws-agent-config.example`: copy to `~/.aws/agent-config` and fill in your start URL, the agent account ID and permission set names.
- `agent-github-token.mjs`: the Claude Code hook that mints the agent GitHub App's installation tokens, one per session, scoped to the repos of the folder the session started in. Copy it to `~/.claude/hooks/`, where sandboxed commands can't edit it; `claude-settings.example.json` runs it at session start and before each Bash command. `node ~/.claude/hooks/agent-github-token.mjs resolve <folder>` shows which repos a session started there would get.
- `agent-github-config.example.json`: copy to `~/.config/agent-github/config.json` and fill in the app ID, the installation ID, and any folders that should map to several repos. The app's private key goes next to it as `app.pem`, readable only by you.

`111122223333` is AWS's documentation placeholder account ID.
