# Dev Machine Specification

## Purpose

What a developer's computer looks like when AI coding agents, such as Claude Code, work on it: the tools agents need, the factory skills, the agents' AWS sign-in, and a sandbox that keeps agents away from the developer's own credentials. Each scenario is checked by [`scripts/check-dev-machine.sh`](../../../scripts/check-dev-machine.sh), run from inside an agent session.

The AWS side follows the [`agent-client` spec](https://github.com/ErikBean/aws-agent-bootstrap/blob/main/openspec/specs/agent-client/spec.md) in aws-agent-bootstrap. This spec doesn't restate those requirements; it adds what agents need beyond AWS, and how the machine gets there.

Reasoning: [agent client decision](https://github.com/ErikBean/research/blob/main/knowledge/projects/aws-agent-bootstrap/decisions/agent-client-setup.md).

## Requirements

### Requirement: The tools agents need are installed for the developer's user

The machine SHALL have git, the GitHub CLI, Node.js 22.12 or later, npm, OpenSpec, AWS CLI v2, Claude Code, and the sandbox's dependencies (bubblewrap and socat on Linux) on the PATH. Node.js, OpenSpec and the AWS CLI SHALL be installed under `~/.local`, so installing them needs no administrator rights. npm SHALL install global packages into `~/.local`.

Reasoning: OpenSpec needs Node.js 22.12 or later. Once the sandbox is on, sandboxed commands can't write to the home folder, so tools are installed by the developer, before the sandbox, where no `sudo` is needed.

#### Scenario: An agent looks for its tools

- **WHEN** a sandboxed command looks up `git`, `gh`, `node`, `npm`, `npx`, `openspec`, `aws`, `claude`, `bwrap` and `socat`
- **THEN** each is on the PATH, and `node` reports 22.12 or later

#### Scenario: npm's global folder

- **WHEN** a command runs `npm config get prefix`
- **THEN** it prints the developer's `~/.local`

### Requirement: The factory skills are linked from one checkout

Each skill in the factory-skills checkout SHALL be linked into `~/.agents/skills/`, and from there into `~/.claude/skills/`, so that pulling the checkout updates every project at once. This repo's `dev-machine-setup` skill SHALL be linked the same way.

#### Scenario: An agent loads a factory skill

- **WHEN** a command reads `~/.claude/skills/factory-orchestrator/SKILL.md`
- **THEN** the file is found, through links into the factory-skills checkout

### Requirement: Claude Code always runs in a strict sandbox

The developer's Claude Code user settings SHALL enable the sandbox, refuse to start without it, refuse to run commands outside it, and disable bypass permissions mode. The sandbox's network SHALL allow only AWS, GitHub and the npm registry. It SHALL let npm write to its cache in `~/.npm`.

Reasoning: the sandbox covers shell commands only ([finding](https://github.com/ErikBean/research/blob/main/knowledge/tech/aws-agent-guardrails/findings/claude-code-sandbox-shell-only.md)), and permission rules on their own aren't a boundary ([finding](https://github.com/ErikBean/research/blob/main/knowledge/tech/aws-agent-guardrails/findings/claude-code-bash-rules-not-a-boundary.md)).

#### Scenario: Reading the settings

- **WHEN** a command reads `~/.claude/settings.json`
- **THEN** `sandbox.enabled` and `sandbox.failIfUnavailable` are true, `sandbox.allowUnsandboxedCommands` is false, and `permissions.disableBypassPermissionsMode` is `disable`

#### Scenario: A command writes to the home folder

- **WHEN** a sandboxed command creates a file directly in the home folder
- **THEN** the write fails

#### Scenario: npm installs a package

- **WHEN** a sandboxed command writes to `~/.npm`
- **THEN** the write succeeds

### Requirement: Agents can't use the developer's own GitHub credentials

Sandboxed commands SHALL NOT be able to read the developer's SSH private keys, SHALL NOT receive `SSH_AUTH_SOCK`, and SHALL NOT be able to connect to the developer's SSH agent. The GitHub CLI's token in the system keyring SHALL be out of their reach. Claude Code SHALL ask before its Read tool opens a file in `~/.ssh`.

Reasoning: the sandbox already kept `gh` away from the keyring, but git over SSH still worked with the developer's key until the key and agent were blocked ([finding](https://github.com/ErikBean/research/blob/main/knowledge/tech/github-agent-access/findings/sandbox-local-test-gh-ssh.md)). Agents get their own GitHub identity instead ([question](https://github.com/ErikBean/research/blob/main/knowledge/tech/github-agent-access/questions/github-agent-access.md)). The Read tool isn't covered by the sandbox ([finding](https://github.com/ErikBean/research/blob/main/knowledge/tech/aws-agent-guardrails/findings/claude-code-read-deny-scope.md)).

#### Scenario: A command reads an SSH private key

- **WHEN** a sandboxed command reads any private key in `~/.ssh`
- **THEN** it gets no key material

#### Scenario: A command finds the SSH agent's socket

- **WHEN** a sandboxed command finds an SSH agent socket on the machine and asks it to list keys
- **THEN** the connection is refused, and `SSH_AUTH_SOCK` isn't set in the command's environment

#### Scenario: git uses SSH

- **WHEN** a sandboxed command runs `git ls-remote` against a GitHub repository over SSH
- **THEN** authentication fails

### Requirement: Agents use AWS only through the agent profiles

Claude Code's settings SHALL point the AWS CLI at the agent-only config file, `~/.aws/agent-config`, with the `agent-builder` profile, as the `agent-client` spec requires. The developer's admin profile SHALL be named `admin` with an SSO session named `admin`, so its token file's name is known before signing in and is denied to sandboxed commands.

Reasoning: the AWS CLI names an SSO session's token file after the SHA-1 of the session name, so fixing the name lets the sandbox deny the file in advance ([agent-client spec](https://github.com/ErikBean/aws-agent-bootstrap/blob/main/openspec/specs/agent-client/spec.md)).

#### Scenario: An agent lists AWS profiles

- **WHEN** a sandboxed command runs `aws configure list-profiles`
- **THEN** it lists only `agent-builder` and `agent-viewonly`

#### Scenario: A command reads the admin token

- **WHEN** a sandboxed command reads the admin session's token file in `~/.aws/sso/cache/`
- **THEN** it gets nothing, whether or not the developer is signed in

#### Scenario: An agent checks who it is in AWS

- **WHEN** the agent user is signed in and a sandboxed command runs `aws sts get-caller-identity`
- **THEN** the role is one of the agent permission sets
