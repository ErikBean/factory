# @favabean/factory-cdk

## 0.3.1

### Patch Changes

- b0f9112: Releases are now made from change notes: each pull request adds one in `.changeset/`, CI requires it, and `npx changeset version` writes the version and `cdk/CHANGELOG.md`, where versions after 0.3.0 are recorded. Before 1.0, a minor version means apps must act, and a patch is everything else. The template's skills check now compares an app's pin with the factory's latest release rather than its `main` branch, so unreleased skill changes no longer show as "behind". ([#22](https://github.com/ErikBean/factory/pull/22))
- b0f9112: `release.sh` no longer takes a missing tag for one at another commit ([#20](https://github.com/ErikBean/factory/pull/20)), and offers to retry the npm approval while npm's automated review is still running, instead of exiting ([#21](https://github.com/ErikBean/factory/pull/21)).
- 5dace95: The `factory-reviewer` skill reports changes to an app's factory pins: a pin to a branch or commit is blocking, and a move to a release is noted. `factory-repo-setup` checks that the agent can't assume the `ci` bootstrap's roles, asks the human to confirm the management account, names the identity for the admin step, and says to ask AWS early to verify the account for CloudFront. ([#27](https://github.com/ErikBean/factory/pull/27))
- b0f9112: The template's skill scripts, CI comment and spec source name refer to the factory, not factory-skills and aws-agent-bootstrap ([#21](https://github.com/ErikBean/factory/pull/21)).

## 0.3.0 and earlier

See [CHANGELOG.md](../CHANGELOG.md) at the repository root.
