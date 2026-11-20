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
| `platform/` (the rest) | Account setup, permissions boundary, the agents' GitHub token hook (from aws-agent-bootstrap, dev-machine and agent-github) | Planned |
| `skills/` | The factory's agent skills (from factory-skills) | Planned |
| `template/` | The starting point for a new app | Planned |

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

It runs only from a clean checkout of `main` as it is on GitHub, checks the
IDs against GitHub, deploys with the admin's own credentials (not
a CDK bootstrap role, since agents can use the dev bootstrap's), asks before any
IAM change, and sets each app's `AWS_ACCOUNT_ID` and `AWS_REGION` variables.

## Releases

A release ships the library and the workflows together. Merging to `main` on
its own reaches no app. To release:

1. In a pull request, set `cdk/package.json`'s version, such as `0.3.0`.
2. After it merges, the admin runs
   `gh release create v0.3.0 --repo ErikBean/factory --target main --generate-notes`.
3. [`publish.yml`](.github/workflows/publish.yml) checks the tag matches the
   version, runs the tests and stages the package on npm through trusted
   publishing, with provenance and no stored token. A prerelease such as
   `v0.3.0-rc.1` goes to npm's `next` dist-tag.
4. The admin checks the staged version (`npm stage list @favabean/factory-cdk`,
   then `npm stage download <id>`) and approves it with 2FA:
   `npm stage approve <id>`, or Approve on npmjs.com. The trusted publisher is
   stage-only, and the workflow's token can't approve, so nothing goes live
   without this step.
5. Dependabot proposes the new release to each app after a week's cooldown.

[`platform/github/release-tags.sh`](platform/github/release-tags.sh), run
once by the admin, makes `v*` tags admin-only to create and impossible to
move or delete, turns on immutable releases, and makes the `npm-publish`
environment, which only runs from `v*` tags can use. npm's trusted publisher
names that environment, so a branch that edits `publish.yml` can't publish.

## License

[Apache-2.0](LICENSE).
