# Changelog

What changed in each factory release, for the apps that use it. Each version is a release tag `v<version>` and the same version of [`@favabean/factory-cdk`](https://www.npmjs.com/package/@favabean/factory-cdk) on npm (0.1.0 predates tags). **Upgrading** says what an app must do to move to that version. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [semantic versioning](https://semver.org/): before 1.0, a minor version may need app changes, and its Upgrading section says which.

**Versions after 0.3.0 are in [`cdk/CHANGELOG.md`](cdk/CHANGELOG.md)**, which Changesets writes from each pull request's change note; [`release.sh`](platform/github/release.sh) uses the version's section as the release notes. See [RELEASING.md](RELEASING.md). This file keeps 0.3.0 and earlier.

## [0.3.0] - 2026-11-22

The factory becomes one repo: the account specs, the platform and the skills move in, and new apps start from a template. The npm package's code is unchanged from 0.2.0.

### Added

- `template/`, the starting point for a new app, filled in by `scripts/create-app.mjs`. CI creates a demo app from it and checks it installs, tests and synthesizes ([#18](https://github.com/ErikBean/factory/pull/18)).
- `platform/github/new-app.sh`, the GitHub side of a new app in one admin command, and `platform/github/repo-rulesets.sh` ([#18](https://github.com/ErikBean/factory/pull/18)).
- `openspec/specs/`: the account, permission and app-environment specs, from aws-agent-bootstrap. Previews are now suspended while the stages share an account ([#5](https://github.com/ErikBean/factory/pull/5)).
- `platform/aws/` (the account setup and its runbook) and `platform/client/` (the developer's machine and the agents' GitHub token hook), from aws-agent-bootstrap ([#5](https://github.com/ErikBean/factory/pull/5)).
- `skills/`, from factory-skills, with its tests and linters in CI ([#6](https://github.com/ErikBean/factory/pull/6)). `factory-repo-setup` is rewritten around the template ([#18](https://github.com/ErikBean/factory/pull/18)).
- A privacy check in CI, refusing account IDs, emails and keys in tracked files ([#5](https://github.com/ErikBean/factory/pull/5)).
- `RELEASING.md`, `platform/github/release.sh` and this changelog ([#19](https://github.com/ErikBean/factory/pull/19)).

### Changed

- `platform/github-oidc/deploy-roles.sh` reads the AWS account from the admin profile and asks to confirm it. `apps.json` no longer names the account. The deployed roles are unchanged ([#5](https://github.com/ErikBean/factory/pull/5)).
- CI caches the linters' pip install and retries it ([#17](https://github.com/ErikBean/factory/pull/17)).

### Upgrading

- Move the three workflows to `@v0.3.0`, and `@favabean/factory-cdk` to `^0.3.0`. Dependabot proposes both.
- In `factory.config.yaml`'s review sources, point the template source at `https://github.com/ErikBean/factory/tree/v0.3.0`, and the spec source, which was aws-agent-bootstrap's specs, at `https://github.com/ErikBean/factory/tree/v0.3.0/openspec/specs`.
- Re-sync the skills from a factory checkout of `v0.3.0`: `scripts/sync-factory-skills.sh <factory checkout>`. `.agents/factory-skills.json`'s source becomes ErikBean/factory.

## [0.2.0] - 2026-11-20

Factory changes reach apps only through protected releases.

### Added

- `publish.yml`: a release stages the package on npm through trusted publishing, with provenance and no stored token. It runs in the `npm-publish` environment, which only `v*` tags can use, and an admin approves each version on npm ([#3](https://github.com/ErikBean/factory/pull/3), [#4](https://github.com/ErikBean/factory/pull/4)).
- `platform/github/release-tags.sh`: `v*` tags only admins can create and nobody can move or delete, immutable releases, and the `npm-publish` environment ([#3](https://github.com/ErikBean/factory/pull/3), [#4](https://github.com/ErikBean/factory/pull/4)).
- The package's `repository` field, which provenance needs ([#3](https://github.com/ErikBean/factory/pull/3)).

### Changed

- The app roles trust the reusable workflows only at a `v*` release tag ([#3](https://github.com/ErikBean/factory/pull/3)).
- The package no longer ships source maps ([#3](https://github.com/ErikBean/factory/pull/3)).

### Upgrading

- Call the factory's workflows at a release tag, such as `@v0.2.0`. At a SHA or a branch, they can't assume the app's roles.

## [0.1.0] - 2026-11-20

The first version, published to npm by hand from `main` (`de97564`). It has no GitHub release or tag.

### Added

- `@favabean/factory-cdk`: `FactoryStack`, `StaticSite` and `factory-dev-slug` ([#1](https://github.com/ErikBean/factory/pull/1)), and `factory-prod-diff` and `factory-check-boundaries` ([#2](https://github.com/ErikBean/factory/pull/2)).
- The reusable workflows `app-ci`, `app-prod-diff`, `app-deploy` and `app-dev-cleanup` ([#2](https://github.com/ErikBean/factory/pull/2)).
- `platform/github-oidc`: each app's deploy and dev cleanup roles from `apps.json`, and `deploy-roles.sh` ([#2](https://github.com/ErikBean/factory/pull/2)).
- The Apache-2.0 license ([#1](https://github.com/ErikBean/factory/pull/1)).

[0.3.0]: https://github.com/ErikBean/factory/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ErikBean/factory/releases/tag/v0.2.0
[0.1.0]: https://www.npmjs.com/package/@favabean/factory-cdk/v/0.1.0
