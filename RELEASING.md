# Releasing the factory

A release is how factory changes reach apps. Merging to `main` alone reaches no app. One release `v<version>` ships everything apps use from the factory at once:

- the reusable workflows, which apps call at `@v<version>` and whose AWS roles trust only `v*` tags;
- `@favabean/factory-cdk@<version>` on npm;
- the specs, skills and `template/` at that tag.

Release when a change should reach the apps. There's no fixed schedule.

## Change notes

Every pull request adds a note in [`.changeset/`](.changeset/README.md), written by whoever makes the change: the bump, and what changed for apps. CI's `scripts/check-changeset.mjs` fails a pull request without one. Changes that release nothing, such as to CI or docs, add an empty note. Dependabot's pull requests pass without one, and the next version-bump pull request covers them.

Versions stay below 1.0 until the factory's public API is written down: what apps rely on, such as the workflows' inputs, the role names and variables, the construct's props and the files the template requires. Until then:

- **minor:** an app must change something to take the release. The note says what, under **Upgrading**.
- **patch:** everything else, new features included.
- **major:** never. Changesets would release 1.0.0, so CI refuses it.

## Steps

| # | Who | Step |
| --- | --- | --- |
| 1 | Agent | Open the version-bump PR. If Dependabot PRs merged since the last release, first add a patch note listing them (`git log v<last>..main --author=dependabot`). Then run `npx changeset version`, which sets `cdk/package.json`'s version from the notes, writes the version's section in [`cdk/CHANGELOG.md`](cdk/CHANGELOG.md) and deletes the notes, and `npm install --package-lock-only --ignore-scripts` for the lockfile. Check the section reads well for an app's maintainer, then commit it all. A prerelease such as `0.4.0-rc.1` goes to npm's `next` dist-tag and is marked as a prerelease on GitHub; see Changesets' `pre` command. |
| 2 | Admin | Review and merge it. |
| 3–6 | Admin | From a clean checkout of `main`, signed in to `gh` as yourself, run `platform/github/release.sh`, which does the rest. |
| 7 | Agent | Open PRs moving each app to the release (below). |

What `release.sh` does, and why:

1. **Checks:** `main` is clean and matches GitHub's, CI's `test` check passed on it, no change notes are waiting in `.changeset/`, `cdk/CHANGELOG.md` has the version's section (or, for 0.3.0 and earlier, `CHANGELOG.md`), and neither the tag nor the npm version exists yet. A release can't be moved or deleted (the `release-tags-locked` ruleset and immutable releases), so it stops before anything changes.
2. **Creates the release** at `main`'s full commit SHA, with the changelog section as its notes, after you confirm. Dependabot passes those notes on in the PRs it opens for apps. Only admins can create `v*` tags (`release-tags-create`). A short SHA as `--target` gets an HTTP 422.
3. **Waits for [`publish.yml`](.github/workflows/publish.yml).** In the `npm-publish` environment, which only `v*` tags can use, the workflow checks the tag matches the version, runs the tests and stages the package on npm through trusted publishing, with provenance and no stored token. The script prints the stage ID.
4. **Approve:** the script shows `npm stage view <id>`: check the version and that GitHub Actions staged it, and look at the files with `npm stage download <id>` if you want (`dist/`, `LICENSE`, `package.json`; provenance comes from that run). Then approve with your npm 2FA: the script offers to run `npm stage approve <id>`, signs you in to npm if needed, and waits until the version is live. npm refuses approval with a 409 until its automated review finishes, which has taken several minutes and which `stage view` doesn't show, so the script waits until 10 minutes after staging before its first try (press Enter to try sooner) and offers to try again after a 409. Afterwards, `npm logout` leaves no npm token on the machine.

## Moving apps to the release

Dependabot proposes the new workflow pins and the npm version to each app a week after the release (its cooldown). To move sooner, an agent opens a PR in each app that:

- follows the version's **Upgrading** notes in [`cdk/CHANGELOG.md`](cdk/CHANGELOG.md), or [CHANGELOG.md](CHANGELOG.md) for 0.3.0 and earlier;
- sets the three workflows to `@v<version>`, `@favabean/factory-cdk` to `^<version>`, and the tag in `factory.config.yaml`'s review sources;
- re-syncs the skills from a factory checkout of the tag: `scripts/sync-factory-skills.sh <factory checkout>`;
- passes the app's CI, and deploys and smoke-tests `dev`.

## When something goes wrong

- **The publish run failed.** The tag stays; it can't be deleted. Fix the cause in a PR, bump to the next patch version, and release again.
- **"doesn't match cdk/package.json's version".** The tag and the package version differ. Bump the version in a PR first; never tag a commit whose version you haven't set.
- **Approval refused, or nothing to approve.** `npm stage list @favabean/factory-cdk` shows what's staged. If the scan is still running, wait and retry.
- **"change notes are waiting".** Notes merged after the version-bump PR. Run `npx changeset version` in another version-bump PR, for the next patch version.
- **"cdk/CHANGELOG.md has no section".** The version-bump PR didn't run `npx changeset version`. Run it in a PR, as step 1 says.
- **`release.sh` stopped partway.** Run it again: it picks up an existing release at `main`'s commit and goes on from the publish run.
