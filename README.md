# factory

The software factory in one repo: the platform it runs on, the CDK constructs and
workflows every app it builds shares, and the agents' skills. The goal is to
spin up a new web app with as few human steps as possible, behind guardrails
against surprise costs and security risks.

| Folder | What | State |
| --- | --- | --- |
| `cdk/` | `@favabean/factory-cdk`, the construct library apps install from npm | Started |
| `.github/workflows/app-*.yml` | Reusable workflows that apps call by release tag. GitHub only runs reusable workflows from `.github/workflows/`, so they live there rather than in a folder of their own | Started |
| `platform/github-oidc/` | Every app's GitHub OIDC deploy and dev cleanup roles, from one app list | Started |
| `platform/aws/` | The AWS account the agents work in: organization, access, permissions boundary, CDK bootstraps, spend controls, security baseline, and its runbook (was aws-agent-bootstrap) | Moved in |
| `platform/client/` | The developer's machine: its setup and check scripts and runbook, Claude Code and AWS client settings, and the agents' GitHub token hook (from aws-agent-bootstrap's `client/` and dev-machine) | Moved in |
| `openspec/` | The requirements: account structure, agent and deploy permissions, app environments, agent client, spend controls, security baseline | Moved in from aws-agent-bootstrap |
| `skills/` | The factory's agent skills, in a format any agent can use, with their tests (was factory-skills). Apps sync the stage skills from a factory release, and the dev machine links them all from the latest one | Moved in |
| `template/` | The starting point for a new app: jello-world's setup with placeholders, filled in by `scripts/create-app.mjs` | Started |

## cdk

- **`FactoryStack`**: the base stack for every app. It reads the stage
  (`-c stage=dev|preview|prod`) and names stacks per branch or pull request. It
  deploys preview and prod through the separate ci bootstrap and adds the
  `project`, `stage` and `branch` tags the cleanup workflows find stacks by. It
  puts the account's permissions boundary on every role, and fails synth if any
  role or user goes without it. Dev and preview stacks delete their data when
  destroyed.
- **`StaticSite`**: a private S3 bucket served through CloudFront with origin
  access control, filled from a local folder on every deploy.
- **`factory-dev-slug <branch>`**: prints the slug dev stacks are named and
  tagged with, so workflows don't keep their own copy of the rule.
- **`factory-prod-diff <before> <after>`**: prints, as Markdown, how a pull
  request's prod stage differs from the templates the last deploy saved.
- **`factory-check-boundaries [cdk.out]`**: fails if any synthesized role or
  user lacks a permissions boundary, including in stacks that aren't
  `FactoryStack`s.

An app's whole CDK code:

```ts
import { App } from "aws-cdk-lib";
import { FactoryStack, StaticSite } from "@favabean/factory-cdk";

const app = new App();
const stack = new FactoryStack(app, "Site", { project: "jello-world" });
new StaticSite(stack, "Site", { source: "site" });
```

`aws-cdk-lib` is a peer dependency pinned to one minor version. The boundary
check renders roles with `_toCloudFormation()`, which CDK marks as internal,
because CDK attaches the boundary to some of its own helper roles as a raw
override. Raise the pin on purpose, with the tests.

The package uses named exports only, never `export *`, so two modules can't
export the same name by accident.

```sh
npm install
npm test      # type-check, build, then jest
```

## Reusable workflows

An app's whole CI and CD is three short workflows that call these at a
release tag, such as `@v0.2.0`, which Dependabot bumps:

| App workflow | On | Calls |
| --- | --- | --- |
| `ci.yml` | `pull_request` | `app-ci.yml` (tests, prod synth, boundary check) and `app-prod-diff.yml` (what the PR changes in production, with no credentials) |
| `deploy.yml` | push to `main` | `app-ci.yml`, then `app-deploy.yml` (deploys prod as `factory-deploy-<repo>`, saves the templates for the diff) |
| `dev-cleanup.yml` | `pull_request_target`, `closed` | `app-dev-cleanup.yml` (deletes the branch's dev stacks as `factory-dev-cleanup-<repo>`) |

Each reusable workflow's header has the stub to copy. They assume the app's
`FactoryStack` project is its repo name, and that the app has the repo
variables `AWS_ACCOUNT_ID` and `AWS_REGION`, which `deploy-roles.sh` sets.

Dev cleanup runs on `pull_request_target` on purpose. GitHub then runs the
default branch's copy of the caller, so the cleanup role can trust the default
branch, as the deploy role does, and the release the app pins is reviewed code. The
workflow checks out the default branch, never the pull request, and skips fork
pull requests, whose branch names could match the repo's own.

## platform/github-oidc

A CDK app that makes two roles per app in [`apps.json`](platform/github-oidc/apps.json):

- **`factory-deploy-<repo>`** can assume only the `ci` bootstrap's roles.
- **`factory-dev-cleanup-<repo>`** can delete only stacks tagged with the app's
  project and `stage=dev`, through the dev bootstrap's execution role.

Both trust only the app's `main` branch, pinned by the repo's and owner's
numeric IDs, running the matching factory workflow at a `v*` release tag. Only
the factory's admin can create those tags, so only released factory code can
hold the roles, whatever an app's pin says. Moving an app to a new release
needs no role change. Both
carry the account's permissions boundary. The account's GitHub OIDC provider is
looked up, not created, since an account has one and it belongs to the
account's setup.

To add an app, add a line to `apps.json` with its repo ID
(`gh api repos/OWNER/NAME -q .id`), then have an admin run:

```sh
platform/github-oidc/deploy-roles.sh <admin-profile>
```

It runs only from a clean checkout of `main` as it is on GitHub, takes the
account from the admin profile and asks you to confirm it (`apps.json` names no
account, so this public repo holds none), checks the IDs against GitHub, deploys with the admin's own credentials (not
a CDK bootstrap role, since agents can use the dev bootstrap's), asks before any
IAM change, and sets each app's `AWS_ACCOUNT_ID` and `AWS_REGION` variables.

## New apps

A new app takes one admin command, one agent step and one more admin command:

1. **Admin:** `platform/github/new-app.sh <name>`, signed in to `gh` as yourself. It creates the public repo, adds it to the agents' GitHub App installation and token config, and gives it the rulesets (`platform/github/repo-rulesets.sh`: a pull request, a passing `test / test`, and the code owner's approval).
2. **Agent**, in a new session so its token covers the repo: clone it, run `node scripts/create-app.mjs <clone> <name>` from a factory checkout of the release to pin, then commit and open the setup pull request. Also open a factory pull request adding the app to `platform/github-oidc/apps.json`. The script copies `template/`, fills in the name, owner and release, and syncs the stage skills.
3. **Admin**, after the `apps.json` change merges: `platform/github-oidc/deploy-roles.sh <admin-profile>` creates the app's roles and sets its repo variables. Then review and merge the setup pull request; the merge deploys to production.

`scripts/test-create-app.sh`, run in CI, creates a demo app this way and checks it installs, tests and synthesizes.

## Releases

A release ships the library, the workflows, the specs, the skills and the
template together. Merging to `main` on its own reaches no app. In short:
every PR adds a change note in [`.changeset/`](.changeset/README.md); an agent
opens a version-bump PR with `npx changeset version`, which turns the notes
into the version and its changelog; after it merges, the admin runs
[`platform/github/release.sh`](platform/github/release.sh), which checks
`main`, creates the release, waits for the package to be staged on npm and
offers to approve it. [`cdk/CHANGELOG.md`](cdk/CHANGELOG.md) (and
[CHANGELOG.md](CHANGELOG.md) up to 0.3.0) says what each release changed and
what apps must do to move to it. [PUBLIC-API.md](PUBLIC-API.md) lists what
apps rely on, which sets what counts as breaking. [RELEASING.md](RELEASING.md)
has the steps, what each checks, moving apps to a release, and what to do when
one goes wrong.

[`platform/github/release-tags.sh`](platform/github/release-tags.sh), run
once by the admin, makes `v*` tags admin-only to create and impossible to
move or delete, turns on immutable releases, and makes the `npm-publish`
environment, which only runs from `v*` tags can use. npm's trusted publisher
names that environment, so a branch that edits `publish.yml` can't publish.

## License

[Apache-2.0](LICENSE).
