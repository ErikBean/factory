# Releasing the factory

A release is how factory changes reach apps. Merging to `main` alone reaches no app. One release `v<version>` ships everything apps use from the factory at once:

- the reusable workflows, which apps call at `@v<version>` and whose AWS roles trust only `v*` tags;
- `@favabean/factory-cdk@<version>` on npm;
- the specs, skills and `template/` at that tag.

Release when a change should reach the apps. There's no fixed schedule.

## Steps

| # | Who | Step |
| --- | --- | --- |
| 1 | Agent | Open a PR that sets `cdk/package.json`'s `version` (and the lockfile, with `npm install --package-lock-only --ignore-scripts`), and adds the version's section to [CHANGELOG.md](CHANGELOG.md): what's Added, Changed and Fixed since the last release, from the PRs merged since its tag, with each PR linked, plus **Upgrading** when apps must act. Use semver: a patch for fixes, a minor for anything new, a major once 1.0 for breaking changes. A prerelease such as `0.4.0-rc.1` goes to npm's `next` dist-tag and is marked as a prerelease on GitHub. |
| 2 | Admin | Review and merge it. |
| 3–6 | Admin | From a clean checkout of `main`, signed in to `gh` as yourself, run `platform/github/release.sh`, which does the rest. |
| 7 | Agent | Open PRs moving each app to the release (below). |

What `release.sh` does, and why:

1. **Checks:** `main` is clean and matches GitHub's, CI's `test` check passed on it, `CHANGELOG.md` has the version's section, and neither the tag nor the npm version exists yet. A release can't be moved or deleted (the `release-tags-locked` ruleset and immutable releases), so it stops before anything changes.
2. **Creates the release** at `main`'s full commit SHA, with the changelog section as its notes, after you confirm. Dependabot passes those notes on in the PRs it opens for apps. Only admins can create `v*` tags (`release-tags-create`). A short SHA as `--target` gets an HTTP 422.
3. **Waits for [`publish.yml`](.github/workflows/publish.yml).** In the `npm-publish` environment, which only `v*` tags can use, the workflow checks the tag matches the version, runs the tests and stages the package on npm through trusted publishing, with provenance and no stored token. The script prints the stage ID.
4. **Approve:** check `npm stage view <id>` (the version, the files: `dist/`, `LICENSE`, `package.json`, and provenance from that run), then approve with your npm 2FA. The script offers to run `npm stage approve <id>`, signs you in to npm if needed, and waits until the version is live. Approval may be unavailable for a few minutes while npm's malware scan runs. Afterwards, `npm logout` leaves no npm token on the machine.

## Moving apps to the release

Dependabot proposes the new workflow pins and the npm version to each app a week after the release (its cooldown). To move sooner, an agent opens a PR in each app that:

- follows the version's **Upgrading** notes in [CHANGELOG.md](CHANGELOG.md);
- sets the three workflows to `@v<version>`, `@favabean/factory-cdk` to `^<version>`, and the tag in `factory.config.yaml`'s review sources;
- re-syncs the skills from a factory checkout of the tag: `scripts/sync-factory-skills.sh <factory checkout>`;
- passes the app's CI, and deploys and smoke-tests `dev`.

## When something goes wrong

- **The publish run failed.** The tag stays; it can't be deleted. Fix the cause in a PR, bump to the next patch version, and release again.
- **"doesn't match cdk/package.json's version".** The tag and the package version differ. Bump the version in a PR first; never tag a commit whose version you haven't set.
- **Approval refused, or nothing to approve.** `npm stage list @favabean/factory-cdk` shows what's staged. If the scan is still running, wait and retry.
- **"CHANGELOG.md has no section".** Add `## [<version>] - <date>` and its entries in a PR, as step 1 says.
- **`release.sh` stopped partway.** Run it again: it picks up an existing release at `main`'s commit and goes on from the publish run.
