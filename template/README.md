# {{name}}

A web app built by the [factory](https://github.com/{{factory}}). It starts as one static page on Amazon S3 behind Amazon CloudFront; replace `site/` and `lib/app.ts` with the app.

## How it ships

Merging to `main` deploys to production. Changes reach `main` only through a pull request whose `test / test` check passed and that the developer approved.

The app is [`lib/app.ts`](lib/app.ts): a `StaticSite` in a `FactoryStack`, both from [`@favabean/factory-cdk`](https://www.npmjs.com/package/@favabean/factory-cdk). The stack carries the platform's rules, so this repo doesn't copy them: the stage, stack names and tags, the `ci` bootstrap for prod, and the `agent-boundary` permissions boundary on every IAM role, checked when it synthesizes.

| Stage | Deployed by | Stack name | CDK bootstrap |
| --- | --- | --- | --- |
| `dev` | The factory, from the developer's machine, as the `agent-builder` profile (`npm run dev:deploy`) | `{{name}}-dev-<branch>-<hash>` | default |
| `prod` | CI, on every merge to `main` | `{{name}}` | `ci` |

While every stage shares one AWS account, there are no per-pull-request previews.

### Workflows

The three workflows here call the factory's reusable workflows at a release tag, such as `@{{release}}`. Dependabot proposes new releases.

| Workflow | On | Does |
| --- | --- | --- |
| [`ci.yml`](.github/workflows/ci.yml) | pull request | Tests, prod synth and boundary check (`test / test`); how the pull request changes production, with no AWS credentials (`prod-diff / prod-diff`); and a warning when the factory skills fall behind |
| [`deploy.yml`](.github/workflows/deploy.yml) | push to `main` | The tests again, then deploys `prod` |
| [`dev-cleanup.yml`](.github/workflows/dev-cleanup.yml) | pull request closed | Deletes that branch's `dev` stacks |

Dev cleanup runs on `pull_request_target`, so GitHub runs `main`'s copy of it, never the pull request's. It checks out `main`, skips pull requests from forks, and takes the branch from the closed pull request itself.

### AWS roles

GitHub Actions reaches AWS through GitHub OIDC, with no stored keys. The roles come from the factory's `platform/github-oidc`, which lists this repo in its `apps.json`:

- `factory-deploy-{{name}}` deploys `prod`.
- `factory-dev-cleanup-{{name}}` can delete only stacks tagged `project={{name}}` and `stage=dev`.

Each trusts only this repo's `main` branch, pinned by the repo's numeric ID, running the matching factory workflow at a release tag: the deploy role on a push to `main`, and the cleanup role for a pull request into `main`. The workflows build the role ARNs from the repo variables `AWS_ACCOUNT_ID` and `AWS_REGION`, which the factory's `deploy-roles.sh` sets.

The admin changes (the roles, the repo variables and the rulesets on `main`) are made by the developer, with their own admin sign-in, never by an agent. Only the developer merges: the `main-review` ruleset needs a code owner's approval of a pull request's latest push, [`CODEOWNERS`](.github/CODEOWNERS) names the developer, and a GitHub App can't be a code owner. [`.claude/hooks/block-merge.mjs`](.claude/hooks/block-merge.mjs) also refuses agents' merge, approve and push-to-`main` commands.

### Factory skills

The factory's stage skills are pinned in `.agents/skills/`, with links from `.claude/skills/`, and the commit they came from is in `.agents/factory-skills.json`. To update them, run `scripts/sync-factory-skills.sh <factory checkout>`. CI's `factory-skills` job warns, without failing, when a pinned skill has changed upstream.

### Checks

```bash
npm test
npx cdk synth --quiet -c stage=prod
npx factory-check-boundaries cdk.out
```
