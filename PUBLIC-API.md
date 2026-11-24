# The factory's public API

What a factory-built app relies on from a factory release. A change that makes an app change something to take a release is breaking:

- Before 1.0, a breaking change is a `minor` change note, with an **Upgrading** line saying what apps must do.
- From 1.0, it's a major version.

Anything not listed here is internal, and can change in any release. See [RELEASING.md](RELEASING.md) and [`.changeset/README.md`](.changeset/README.md).

The factory goes to 1.0 once this list is reviewed and complete.

## Releases and pins

A release `v<version>` ships everything below at once. An app takes it by pinning, all at the same version:

- the three workflow stubs at `ErikBean/factory/.github/workflows/<workflow>@v<version>`;
- `@favabean/factory-cdk` at `^<version>` in `package.json`;
- the review sources in `factory.config.yaml` at `https://github.com/ErikBean/factory/tree/v<version>`;
- the skills in `.agents/factory-skills.json`, synced from a checkout of the release.

Release notes are each version's section of [`cdk/CHANGELOG.md`](cdk/CHANGELOG.md), and [CHANGELOG.md](CHANGELOG.md) for 0.3.0 and earlier.

## Reusable workflows

All read the Node.js version from the app's `.nvmrc`, and install with `npm ci`, so an app uses npm and commits its `package-lock.json`. `app-deploy.yml` and `app-dev-cleanup.yml` install with `--ignore-scripts`, so a deploy can't depend on install scripts, even though `app-ci.yml` runs them.

| Workflow | Called from | Inputs | Caller's permissions | What it does |
| --- | --- | --- | --- | --- |
| `app-ci.yml` | Pull requests, and before each deploy | None | `contents: read` | `npm ci`, `npm test`, `npx cdk synth --quiet -c stage=prod`, `npx factory-check-boundaries cdk.out` |
| `app-prod-diff.yml` | Pull requests | `deploy-workflow`, default `deploy.yml` | `contents: read`, `actions: read` | Compares the pull request's prod stage with the `prod-templates` artifact of `deploy-workflow`'s last successful run on the default branch, as a job summary. No AWS credentials |
| `app-deploy.yml` | Pushes to `main` | `aws-account-id`, `aws-region` (both required) | `contents: read`, `id-token: write` | Assumes `factory-deploy-<repo>`, runs `npx cdk deploy --all --require-approval never -c stage=prod`, and uploads `cdk.out/*.template.json` as the `prod-templates` artifact, kept 90 days |
| `app-dev-cleanup.yml` | `pull_request_target`, `closed`, from the same repo only | `aws-account-id`, `aws-region` (both required), `cdk-qualifier`, default `hnb659fds` | `contents: read`, `id-token: write` | Assumes `factory-dev-cleanup-<repo>`, and deletes the stacks tagged `project=<repo>`, `stage=dev` and `branch=<the closed branch's slug>`, through the bootstrap's execution role |

The app's job that calls `app-ci.yml` on pull requests is named `test`, because the `main` ruleset requires the check `test / test`.

## AWS roles and repo variables

`platform/github-oidc` creates two roles per app listed in `apps.json` (`{"repo": "<name>", "id": <repo ID>}`), and `deploy-roles.sh` sets the app's repo variables `AWS_ACCOUNT_ID` and `AWS_REGION`, which the stubs pass to the workflows.

| Role | Trusted for | Can |
| --- | --- | --- |
| `factory-deploy-<repo>` | The app's `main` branch, by repo ID, running `app-deploy.yml` at a `v*` tag | Assume the `ci` bootstrap's roles (`cdk-<ciQualifier>-*`), for 1 hour |
| `factory-dev-cleanup-<repo>` | The app's `main` branch, by repo ID, running `app-dev-cleanup.yml` at a `v*` tag | Describe stacks, and delete stacks tagged with the app's project and `stage=dev`, for 1 hour |

The roles match the OIDC subject `repo:<owner>/<repo>:ref:refs/heads/main`, in both its plain and its owner-and-repo-ID forms:
- The app's default branch must be named `main`.
- A job that references a GitHub environment gets a different subject, so the deploy and cleanup jobs mustn't use one.

## The library, `@favabean/factory-cdk`

It needs `aws-cdk-lib` at one minor version, `~2.277.0` in 0.3.x, because the boundary check reads CDK internals, and `constructs` `^10.5.0`. A release that raises either is breaking.

- **`FactoryStack`**, `new FactoryStack(app, id, props)`, where `props` is `StackProps` without `stackName` and `synthesizer`, plus:
  - `project` (required): the app's GitHub repo name. The dev cleanup finds and may delete only stacks tagged `project=<repo>`, so a different value leaves dev stacks behind, silently;
  - `boundaryName`: defaults to the `@aws-cdk/core:permissionsBoundary` context value's name, then `agent-boundary`.

  It provides:
  - **Stages:** reads the stage from context. `-c stage=dev -c branch=<branch>`, `-c stage=preview -c pr=<number>` or `-c stage=prod`. Preview and prod also need `ciQualifier` in `cdk.json`'s context.
  - **Stack names and tags:** names the stack `<project><stage.suffix>`, and tags it `project`, `stage`, and `branch` for dev. The suffix is:
    - `""` for prod;
    - `-dev-<slug>` for dev, where `devSlug(branch)` is up to 50 readable characters of the branch, a `-`, and the first 8 hex characters of the branch name's SHA-256;
    - `-preview-pr<number>` for preview.

    Changing a suffix renames deployed stacks: prod's next deploy creates new stacks with new URLs and leaves the old ones, whose buckets are kept. It also stops the cleanup finding existing dev stacks.
  - **Dev and preview data:** in dev and preview, every resource in the stack is deleted with it (`RemovalPolicies.of(stack).destroy()`), which the dev cleanup relies on.
  - **The boundary:** puts the permissions boundary on every IAM role and user, and fails synth for any without one.
  - **Members:** `stage`, `project`, and `addUrl(id, url)`, which outputs `Url<id>`.
- **`Stage`**: `name` (`dev`, `preview` or `prod`), `suffix`, `ephemeral` (true for dev and preview, whose data is deleted with their stacks), `branch` (dev's slug) and `qualifier`. `stageFromContext(scope)` and `devSlug(branch)` compute them.
- **`StaticSite`**, `new StaticSite(stack, id, { source, indexDocument? })`: a private S3 bucket behind CloudFront with origin access control, filled from `source` on each deploy, and deleted with the stack in dev and preview. It has `bucket`, `distribution` and `url`, and outputs its URL through `addUrl`.
- **`FunctionUrlSite`**, `new FunctionUrlSite(stack, id, { source, indexDocument? })`: the same site served by a Lambda function URL, with no CloudFront or bucket, for accounts AWS hasn't verified for CloudFront. It has `function` and `url`, and outputs its URL through `addUrl`. Switching between it and `StaticSite` changes the URL.
- **Types:** `FactoryStackProps`, `StaticSiteProps`, `FunctionUrlSiteProps`, `Stage` and `StageName`, which apps may import.
- **Functions:** `resourcesWithoutBoundary(cdkOut)`, `prodDiffMarkdown(before, after)` and `functionUrlSiteHandler(indexDocument)`.
- **Commands:**
  - `factory-check-boundaries [cdk.out]` fails if a synthesized role or user has no boundary;
  - `factory-dev-slug <branch>` prints the dev slug;
  - `factory-prod-diff <before dir> <after dir>` prints the prod diff as Markdown.

## What an app repo has

From [`template/`](template), which `scripts/create-app.mjs` fills in:

- **`package.json` scripts:** `test`, plus:
  - `dev:deploy`, which writes `cdk-outputs.dev.json`;
  - `dev:smoke`, which needs a 200 containing the app's text from every `Url*` output;
  - `dev:destroy`.
- **`cdk.json` context:** `ciQualifier` and `@aws-cdk/core:permissionsBoundary`.
- **Node.js:** `.nvmrc` names the version.
- **Workflows:**
  - `ci.yml`, with jobs `test` (`app-ci.yml`), `prod-diff` (`app-prod-diff.yml`) and `factory-skills` (`scripts/check-factory-skills.mjs`);
  - `deploy.yml`, run on pushes to `main`, with `test`, then `deploy` (`app-deploy.yml`, given `vars.AWS_ACCOUNT_ID` and `vars.AWS_REGION`);
  - `dev-cleanup.yml`.
- **`factory.config.yaml`:** the keys the factory skills read, as [the orchestrator's config reference](skills/factory-orchestrator/references/config.md) describes.
- **Skills:** `.agents/factory-skills.json` (`source`, `commit` and `skills`), with `scripts/sync-factory-skills.sh` and `scripts/check-factory-skills.mjs`.
- **Dependabot:** `.github/dependabot.yml` proposes new factory releases, for the workflow pins and the npm package, after a 7-day cooldown. It ignores minor and major updates to `aws-cdk-lib`, so apps stay on the library's pinned minor.
- **The merge door:**
  - `.github/CODEOWNERS` names the developer as code owner of every file.
  - `.claude/settings.json` runs `.claude/hooks/block-merge.mjs`, which refuses agents' merge, approve and push-to-`main` commands.
- **GitHub rulesets**, from `platform/github/repo-rulesets.sh`:
  - `main`: a pull request with the `test / test` check passing, and no force pushes;
  - `main-review`: a code owner's approval of the latest push, which repository admins can bypass only through a pull request.

## Skills

Apps sync the stage skills: `factory-implementer`, `factory-observer`, `factory-orchestrator`, `factory-releaser`, `factory-reviewer`, `factory-spec-writer`, `factory-test-writer` and `factory-verifier`. Each skill's name and the `factory.config.yaml` keys an app sets are part of the API.

What a skill does inside a stage, and the handoff format between stages, aren't. An app syncs every stage skill from one release at once, so the handoff never crosses versions inside an app.

## Not part of it

These can change in any release:
- The admin tooling in `platform/`, apart from the roles and variables above.
- The starter app in the template: `bin/`, `lib/app.ts`, `site/`, its tests and `README.md`. Apps own those once created.
- Library code that `src/index.ts` doesn't export.
- This repo's own CI, scripts and docs.
- The wording of `openspec/specs/`. A change to a requirement that apps must act on still counts as breaking.
