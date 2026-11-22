# platform/aws

The AWS account where one developer lets AI coding agents, such as Claude Code, create things without surprise costs, security holes or a mess to clean up: the organization, the agent and admin access, the permissions boundary and its CDK bootstraps, spend controls and the security baseline.

This was [ErikBean/aws-agent-bootstrap](https://github.com/ErikBean/aws-agent-bootstrap), moved into the factory unchanged apart from paths. Its history stays there.

- Requirements: the factory's [`openspec/specs/`](../../openspec/specs), especially [`account-structure`](../../openspec/specs/account-structure/spec.md), [`deploy-permissions`](../../openspec/specs/deploy-permissions/spec.md), [`agent-permissions`](../../openspec/specs/agent-permissions/spec.md), [`spend-controls`](../../openspec/specs/spend-controls/spec.md) and [`security-baseline`](../../openspec/specs/security-baseline/spec.md).
- Code: [`infra/`](infra) holds the CloudFormation templates, deployed by the scripts in [`scripts/`](scripts). Run the scripts from this folder. Real account values are read from gitignored config in `config.local/`.
- Manual steps: [`RUNBOOK.md`](RUNBOOK.md).
- The developer's machine: [`../client/`](../client). Each app's GitHub OIDC roles: [`../github-oidc/`](../github-oidc).

Status: `account-structure`, `deploy-permissions` and `agent-permissions` have code. Until the organization's account quota allows member accounts, the runbook's interim section runs agents and apps in the management account.

This repo is public and contains no values from a real account. See the factory's [AGENTS.md](../../AGENTS.md) for how that is kept true.
