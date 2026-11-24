# @favabean/factory-cdk

## 0.3.3

### Patch Changes

- 821b061: Adds a `research` key to `factory.config.yaml`: where an app's research lives, as a folder in a knowledge bundle. The spec stage reads it and proposes requirements from its recommendations, each citing its source; the orchestrator lists them at the spec review, where the human decides; and the reviewer checks the code follows them. The template and `factory-repo-setup` ask for it. Apps that don't set it are unaffected ([#35](https://github.com/ErikBean/factory/pull/35)).

## 0.3.2

### Patch Changes

- 5c89ab8: Adds `FunctionUrlSite`: a static site served over HTTPS by a Lambda function URL, with no CloudFront or S3, for accounts AWS hasn't verified for CloudFront yet. It takes the same props as `StaticSite`; switching between them changes the site's URL. The account runbook and `factory-repo-setup` say when to use it. ([#33](https://github.com/ErikBean/factory/pull/33))
- [`PUBLIC-API.md`](https://github.com/ErikBean/factory/blob/main/PUBLIC-API.md) lists what apps rely on from a release, which sets what counts as a breaking change ([#31](https://github.com/ErikBean/factory/pull/31)).

## 0.3.1

### Patch Changes

- b0f9112: Releases are now made from change notes: each pull request adds one in `.changeset/`, CI requires it, and `npx changeset version` writes the version and `cdk/CHANGELOG.md`, where versions after 0.3.0 are recorded. Before 1.0, a minor version means apps must act, and a patch is everything else. The template's skills check now compares an app's pin with the factory's latest release rather than its `main` branch, so unreleased skill changes no longer show as "behind". ([#22](https://github.com/ErikBean/factory/pull/22))
- b0f9112: `release.sh` no longer takes a missing tag for one at another commit ([#20](https://github.com/ErikBean/factory/pull/20)), and offers to retry the npm approval while npm's automated review is still running, instead of exiting ([#21](https://github.com/ErikBean/factory/pull/21)).
- 5dace95: The `factory-reviewer` skill reports changes to an app's factory pins: a pin to a branch or commit is blocking, and a move to a release is noted. `factory-repo-setup` checks that the agent can't assume the `ci` bootstrap's roles, asks the human to confirm the management account, names the identity for the admin step, and says to ask AWS early to verify the account for CloudFront. ([#27](https://github.com/ErikBean/factory/pull/27))
- b0f9112: The template's skill scripts, CI comment and spec source name refer to the factory, not factory-skills and aws-agent-bootstrap ([#21](https://github.com/ErikBean/factory/pull/21)).

## 0.3.0 and earlier

See [CHANGELOG.md](../CHANGELOG.md) at the repository root.
