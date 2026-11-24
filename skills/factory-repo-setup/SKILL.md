---
name: factory-repo-setup
description: Sets up a new app repo for the software factory from the factory's template, so the factory can build in it and every merge to main deploys to production. The human runs two admin commands (new-app.sh for the GitHub side, deploy-roles.sh for the AWS roles); the agent creates the app from template/ with create-app.mjs, opens the setup pull request and the apps.json change, and deploys and smoke-tests dev. Use only when the human asks to set up a new app or repo for the factory.
---

# Factory repo setup

You set up a new app repo from the factory's `template/`, so the factory can build in it and every merge to `main` deploys to production. The factory supplies everything shared: the construct library (`@favabean/factory-cdk`), the reusable workflows, the roles in `platform/github-oidc/`, and the stage skills. The app repo holds only its own code and three short workflows. [jello-world](https://github.com/ErikBean/jello-world) is the first app set up this way.

The setup has seven steps. Two of them are the human's, run in their own terminal with their own sign-in. Agents never hold an admin session, and never run admin commands themselves (factory#16).

**Say which step you're on.** Start each message during the setup with `Step N of 7:` and what's next. The human may be following on a phone, where they see your messages but not your tool calls (factory#12).

**Admin commands go one at a time.** Give the human one command, say what it does and what success looks like, and wait for their result before the next. Every command here is safe to re-run after a failure (factory#16).

## Step 1: Read what's decided, then ask for the rest

Don't ask the human for what the factory already records (factory#9). Read these from a checkout of [ErikBean/factory](https://github.com/ErikBean/factory) at its latest release (`git tag --list 'v*' --sort=-v:refname | head -1`):

- `platform/github-oidc/apps.json`: the GitHub owner, the factory repo, the Region and the bootstrap qualifiers.
- `openspec/specs/account-structure/spec.md`: which accounts the stages use. While the interim requirement applies, every stage shares one account and there are no previews.
- `platform/aws/README.md` and `RUNBOOK.md`: how the account is set up.

Then ask only for:

- The app's name: lowercase letters, digits and hyphens, starting with a letter. It names the repo, its stacks and its roles.
- A one-line description, for the repo.
- Whether the repo is **public or private**. Rulesets, which guard the merge-to-deploy path, apply to a private repo only on a paid plan such as GitHub Pro, so private needs the human's account on Pro. Without it, the repo must be public.

Check your tools: `gh auth status` (with the agents' GitHub App it shows the app's `[bot]` account), `node --version` (22.12 or later), and `aws sts get-caller-identity` with the agents' `dev` profile, normally `agent-builder`. Sign in as the agent user, never as the human's admin (factory#11). If a sign-in has expired, ask the human to sign the agent user in, by phone with the device-code flow if they're away.

The observer is on if `${XDG_CONFIG_HOME:-~/.config}/factory/observer.yaml` exists, or if the human asks. See [The observer](#the-observer).

## Step 2: Check the account

All read-only, with the agent profile, apart from the test role assumptions, which print nothing secret. Stop and tell the human if one fails: the fix belongs in `platform/aws/`, not in the app (factory#10).

- **Both bootstraps carry the boundary.** `aws cloudformation describe-stacks --stack-name CDKToolkit` and `--stack-name CDKToolkit-ci`, reading `Parameters`: `InputPermissionsBoundary` is `agent-boundary` and `ApplyPermissionsBoundaryToAllRoles` is `true` on both.
- **The GitHub OIDC provider exists.** `aws iam list-open-id-connect-providers` shows one ending in `token.actions.githubusercontent.com`. The roles look it up rather than create it.
- **The management account, during the interim.** If the account is the organization's management account, that's expected while the interim requirement applies: say so, note that service control policies don't protect it, and ask the human to confirm it in this session, even though the spec records it (factory#10).
- **The builder can't reach the `ci` bootstrap.** While the stages share an account, this is what keeps agents from deploying to production. As the agent profile, `aws sts assume-role --role-session-name check --query AssumedRoleUser.Arn --output text --role-arn <arn>` must fail with AccessDenied for `cdk-<ci qualifier>-deploy-role-<account>-<region>` and `cdk-<ci qualifier>-file-publishing-role-<account>-<region>`, and succeed for `cdk-<dev qualifier>-lookup-role-<account>-<region>`. Query only `AssumedRoleUser.Arn`, so no credentials are printed. The qualifiers are `ciQualifier` and `devQualifier` in `apps.json` (factory#10).
- **CloudFront works in the account.** A new AWS account must be verified by AWS Support before it can create CloudFront distributions, and there's no read-only check. Ask the human whether the account already serves a CloudFront distribution, or has been verified. If not, point them to `platform/aws/RUNBOOK.md`'s "Ask AWS to verify each account for CloudFront" now, since it can take days. If step 6's `dev` deploy fails with "Your account must be verified", the same section says what to put in the case, with the error's request ID.

## Step 3: The GitHub side (human)

Give the human, from a factory checkout on `main`:

```bash
platform/github/new-app.sh <name> "<description>"             # public
platform/github/new-app.sh --private <name> "<description>"   # private, with GitHub Pro
```

It creates the repo, has the human add it to the agents' GitHub App installation on the app's settings page, adds it to the agents' token config, and gives it the factory's rulesets: a pull request with a passing `test / test`, and the code owner's approval. Success ends with "Done", the repo's ID and the next steps.

Then ask the human to start a new agent session in the same folder, because a session's GitHub token covers only the repos listed when it started. Continue there.

## Step 4: Create the app and open its pull requests

1. Clone the new repo, and check out the factory at its latest release in a separate clone, so the app pins that release.
2. Run `node <factory>/scripts/create-app.mjs <clone> <name>` from that checkout. It copies `template/`, fills in the name, owner and release, and syncs the stage skills. In a Claude Code sandbox, the skills sync can't write `.claude/` (factory#7): when it fails, give the human the `scripts/sync-factory-skills.sh <factory checkout>` command it prints, to run in the app.
3. In the app: `npm install`, then `npm test`, `npx cdk synth --quiet -c stage=prod` and `npx factory-check-boundaries cdk.out`. All must pass.
4. Commit on a branch, as two commits: the synced skills (`.agents/`, `.claude/skills/` and the sync scripts), then the rest. Push and open the setup pull request against `main`.
5. In the factory, open a pull request adding `{"repo": "<name>", "id": <id>}` to `platform/github-oidc/apps.json`. Get the ID with `gh api repos/<owner>/<name> --jq .id`.

## Step 5: The AWS roles (human)

When the human has reviewed and merged the `apps.json` pull request, give them, from a clean factory checkout of `main`:

```bash
platform/github-oidc/deploy-roles.sh <admin-profile>
```

Say to sign in first as their own Identity Center user with the admin permission set, through their admin profile, not as the agent user. The profile name, such as `admin`, isn't a user name (factory#11). It asks them to confirm the account, shows the IAM changes and asks again before changing anything. It creates `factory-deploy-<name>` and `factory-dev-cleanup-<name>`, and sets the app's `AWS_ACCOUNT_ID` and `AWS_REGION` variables. Ask them to paste the output's last lines. Then ask them to sign out of the admin session by deleting its token file, `rm ~/.aws/sso/cache/d033e22ae348aeb5660fc2140aec35850c4da997.json` (the SHA-1 of the session name `admin`), not with `aws sso logout`, which also signs out the agent that step 6 deploys as (factory#11).

## Step 6: Deploy and test dev

On the setup branch, with the agent profile: `npm run dev:deploy`, then `npm run dev:smoke`. Send the human the `dev` URL from the output, so they can look before merging. The `dev` stack stays up while the pull request is open, and CI deletes it when the pull request closes.

## Step 7: Hand over and report

The human reviews and merges the setup pull request. Merging is theirs alone: never merge, approve or push to `main`. After the merge, watch the `Deploy` run (the first production deploy, through the deploy role) and the `Dev cleanup` run (the `dev` stack deleted through the cleanup role), and report:

- The setup and `apps.json` pull requests, the production URL, and both runs' results.
- **Friction:** how many steps the human took, and the time from step 1 to the first production deploy. The factory is judged on these, so count honestly, including retries and waiting on AWS.
- Anything that didn't go as this skill says, as a suggested change to this skill or the template.

## The observer

The observer is a sub agent that uses the `factory-observer` skill. It notes how the setup went, for whoever maintains the factory, and writes to a knowledge bundle outside the repo. It never changes anything, and nothing it returns is a gate.

The run id is `<YYYY-MM-DD>-setup-<name>`. Start every observer prompt with: "You are the observer of a factory repo setup. Use the `factory-observer` skill." Then give the mode, the run id, the repo's URL, and the factory checkout's path.

- **observe**, after **every** step (factory#15): what you did, the commands you ran or gave the human and what they reported, anything that failed and how you got past it, and what the human said, in their words. Leave out secrets and credential values. One observer at a time.
- **retro**, as part of step 7, with your report. Ask the human its questions, and say they can skip any.
- **write**, with the human's answers. Tell the human where the notes went.

If the setup stops for good partway, run the retro and write anyway.
