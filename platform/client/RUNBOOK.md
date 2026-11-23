# Runbook: set up a dev machine

The order of steps for a new computer, including those an agent can't do. Run them yourself, in your own terminal; Claude can walk you through them with the `dev-machine-setup` skill once Claude Code is installed.

It assumes the AWS account is already set up by [aws-agent-bootstrap](https://github.com/ErikBean/aws-agent-bootstrap), so the agent user and its permission sets exist.

**The order matters.** Tools go on before Claude Code's sandbox, because sandboxed commands can't install into your home folder. Signing in comes after the config files exist, so each sign-in lands on the right profile.

## 1. System packages and Claude Code

These need administrator rights or a vendor installer, so the setup script only checks for them:

```bash
sudo apt install git curl unzip bubblewrap socat
```

- The GitHub CLI: follow https://github.com/cli/cli#installation.
- Claude Code: follow https://code.claude.com/docs/en/setup. Don't start it yet.

## 2. Sign in to GitHub as yourself

```bash
gh auth login        # GitHub.com, SSH, and let it upload or pick your SSH key
```

This is your own login. Agents won't be able to use it once the sandbox is on.

## 3. Clone this repo and fill in its config

```bash
mkdir -p ~/Code && cd ~/Code
git clone git@github.com:ErikBean/dev-machine.git && cd dev-machine
mkdir -p config.local && cp config/machine.env.example config.local/machine.env
```

Edit `config.local/machine.env`. The values come from the AWS console, signed in to your management account:

- `SSO_START_URL` and `SSO_REGION`: **IAM Identity Center → Dashboard → Settings summary**, "AWS access portal URL" and its Region.
- `ADMIN_ACCOUNT_ID`, `AGENT_ACCOUNT_ID`: **IAM Identity Center → AWS accounts**. While aws-agent-bootstrap runs in its interim setup, both are the management account.
- The role names: **IAM Identity Center → Permission sets**.

## 4. Run the setup script

```bash
scripts/setup-dev-machine.sh
```

It installs Node.js, OpenSpec and the AWS CLI under `~/.local`, links the factory skills and the `dev-machine-setup` skill, writes your `admin` AWS profile and `~/.aws/agent-config`, and writes `~/.claude/settings.json`. It finishes with a list of anything left to do.

It never overwrites a file that's different from what it would write. It writes `<file>.proposed` next to it instead. Compare the two, merge what you want, and delete the `.proposed` file.

Open a new terminal afterwards, so `~/.local/bin` is on your PATH.

## 5. Sign the agent in to AWS

The agent user signs in with its own config file. Use a **private browser window**, so the login can't reuse your own portal session:

```bash
AWS_CONFIG_FILE=~/.aws/agent-config aws sso login --sso-session agent --no-browser
```

1. Open the printed URL in a private window.
2. Sign in as the **agent user**, and check the page shows that user before you approve.
3. Close the private window.

If you approve as yourself by mistake, the agent's sign-in carries your token. Run `AWS_CONFIG_FILE=~/.aws/agent-config aws sso logout` and start again.

The sign-in lasts as long as the agent permission sets allow, 4 hours in aws-agent-bootstrap. Repeat this step when it expires.

## 6. Sign in as admin only when you need it

You don't need your admin sign-in for agents to work. When you do need it:

```bash
aws sso login --profile admin
# ... your admin work ...
rm ~/.aws/sso/cache/d033e22ae348aeb5660fc2140aec35850c4da997.json
```

That file is your admin session's token: its name is the SHA-1 of the session name `admin`. Deleting it signs out only your admin session. `aws sso logout` would sign out the agent too.

## 7. Start Claude Code and check the machine

```bash
cd ~/Code && claude
```

Ask Claude to run `dev-machine/scripts/check-dev-machine.sh`. Every line should be `ok` or `skip`. A `skip` says what's missing, such as an AWS sign-in.

## Not covered yet

- **The agents' own GitHub identity.** Until it exists, agents can't push or open pull requests: your SSH key and `gh` login are blocked, and nothing replaces them yet. The plan is a GitHub App, with a Claude Code hook that mints short-lived tokens for agents. See [the research](https://github.com/ErikBean/research/blob/main/knowledge/tech/github-agent-access/questions/github-agent-access.md).
- **macOS.** The scripts assume Linux on x86-64.
