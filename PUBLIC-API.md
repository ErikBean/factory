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

All read the Node.js version from the app's `.nvmrc`.

| Workflow | Called from | Inputs | Caller's permissions | What it does |
| --- | --- | --- | --- | --- |
| `app-ci.yml` | Pull requests, and before each deploy | None | `contents: read` | `npm ci`, `npm test`, `npx cdk synth --quiet -c stage=prod`, `npx factory-check-boundaries cdk.out` |
| `app-prod-diff.yml` | Pull requests | `deploy-workflow`, default `deploy.yml` | `contents: read`, `actions: read` | Compares the pull request's prod stage with the `prod-templates` artifact of `deploy-workflow`'s last successful run on the default branch, as a job summary. No AWS credentials |
| `app-deploy.yml` | Pushes to `main` | `aws-account-id`, `aws-region` (both required) | `contents: read`, `id-token: write` | Assumes `factory-deploy-<repo>`, runs `npx cdk deploy --all --require-approval never -c stage=prod`, and uploads `cdk.out/*.template.json` as the `prod-templates` artifact, kept 90 days |
| `app-dev-cleanup.yml` | `pull_request_target`, `closed`, from the same repo only | `aws-account-id`, `aws-region` (both required), `cdk-qualifier`, default `hnb659fds` | `contents: read`, `id-token: write` | Assumes `factory-dev-cleanup-<repo>`, and deletes the stacks tagged `project=<repo>`, `stage=dev` and `branch=<the closed branch's slug>`, through the bootstrap's execution role |

The app's job that calls `app-ci.yml` on pull requests is named `test`, because the `main-review` ruleset requires the check `test / test`.

## AWS roles and repo variables

`platform/github-oidc` creates two roles per app listed in `apps.json` (`{"repo": "<name>", "id": <repo ID>}`), and `deploy-roles.sh` sets the app's repo variables `AWS_ACCOUNT_ID` and `AWS_REGION`, which the stubs pass to the workflows.

| Role | Trusted for | Can |
| --- | --- | --- |
| `factory-deploy-<repo>` | The app's `main` branch, by repo ID, running `app-deploy.yml` at a `v*` tag | Assume the `ci` bootstrap's roles (`cdk-<ciQualifier>-*`), for 1 hour |
| `factory-dev-cleanup-<repo>` | The app's `main` branch, by repo ID, running `app-dev-cleanup.yml` at a `v*` tag | Describe stacks, and delete stacks tagged with the app's project and `stage=dev`, for 1 hour |

The roles match the OIDC subject `repo:<owner>/<repo>:ref:refs/heads/main`, in both its plain and its owner-and-repo-ID forms. A job that references a GitHub environment gets a different subject, so the deploy and cleanup jobs mustn't use one.

## The library, `@favabean/factory-cdk`

It needs `aws-cdk-lib` at one minor version, `~2.277.0` in 0.3.x, because the boundary check reads CDK internals. A release that raises it is breaking.

- **`FactoryStack`**, `new FactoryStack(app, id, props)`, where `props` is `StackProps` without `stackName` and `synthesizer`, plus:
  - `project` (required): the app's name;
  - `boundaryName`: defaults to the `@aws-cdk/core:permissionsBoundary` context value's name, then `agent-boundary`.

  It provides:
  - **Stages:** reads the stage from context. `-c stage=dev -c branch=<branch>`, `-c stage=preview -c pr=<number>` or `-c stage=prod`. Preview and prod also need `ciQualifier` in `cdk.json`'s context.
  - **Stack names and tags:** names the stack `<project><stage.suffix>`, and tags it `project`, `stage`, and `branch` for dev.
  - **The boundary:** puts the permissions boundary on every IAM role and user, and fails synth for any without one.
  - **Members:** `stage`, `project`, and `addUrl(id, url)`, which outputs `Url<id>`.
- **`Stage`**: `name` (`dev`, `preview` or `prod`), `suffix`, `ephemeral` (true for dev and preview, whose data is deleted with their stacks), `branch` (dev's slug) and `qualifier`. `stageFromContext(scope)` and `devSlug(branch)` compute them.
- **`StaticSite`**, `new StaticSite(stack, id, { source, indexDocument? })`: a private S3 bucket behind CloudFront with origin access control, filled from `source` on each deploy, and deleted with the stack in dev and preview. It has `bucket`, `distribution` and `url`, and outputs its URL through `addUrl`.
- **Functions:** `resourcesWithoutBoundary(cdkOut)` and `prodDiffMarkdown(before, after)`.
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
  - `ci.yml`, with jobs `test` (`app-ci.yml`) and `prod-diff`;
  - `deploy.yml`, run on pushes to `main`, with `test`, then `deploy` (`app-deploy.yml`, given `vars.AWS_ACCOUNT_ID` and `vars.AWS_REGION`);
  - `dev-cleanup.yml`.
- **`factory.config.yaml`:** the keys the factory skills read, as [the orchestrator's config reference](skills/factory-orchestrator/references/config.md) describes.
- **Skills:** `.agents/factory-skills.json` (`source`, `commit` and `skills`), with `scripts/sync-factory-skills.sh` and `scripts/check-factory-skills.mjs`.
- **GitHub:** the `main-review` ruleset, which requires a pull request with `test / test` passing and the code owner's approval.

## Skills

Apps sync the stage skills: `factory-implementer`, `factory-observer`, `factory-orchestrator`, `factory-releaser`, `factory-reviewer`, `factory-spec-writer`, `factory-test-writer` and `factory-verifier`. Each of these is part of the API:
- a skill's name;
- the `factory.config.yaml` keys an app sets;
- the handoff format between stages.

What a skill does inside a stage is not.

## Not part of it

These can change in any release:
- The admin tooling in `platform/`, apart from the roles and variables above.
- The starter app in the template: `bin/`, `lib/app.ts`, `site/`, its tests and `README.md`. Apps own those once created.
- Library code that `src/index.ts` doesn't export.
- This repo's own CI, scripts and docs.
- The wording of `openspec/specs/`. A change to a requirement that apps must act on still counts as breaking.
