// The GitHub OIDC roles for every factory-built app in one account: a deploy
// role and a dev cleanup role per app, from one app list (apps.json). Adding an
// app is one line there plus one admin deploy.
//
// Each role trusts only its app's default branch, running one of the
// factory's reusable workflows at a release tag. For the deploy role, which
// runs on a push to main, the sub claim pins the branch. The dev cleanup runs
// on pull_request_target, whose sub is the repo's pull_request form instead,
// so its role pins the ref claim, the pull request's base branch, to main.
// That keeps it to main's copy of the cleanup workflow. job_workflow_ref pins the workflow and requires a v* tag, which only
// the factory's admin can create and nobody can move (the release-tags
// ruleset), so only released factory code ever holds these roles, whatever an
// app's pin says. An app moves to a new release without a role change.
// job_workflow_ref also keeps the two roles apart: the cleanup workflow can't
// deploy, and the deploy workflow can't clean up. repository_id and
// repository_owner_id pin the repo even if it's renamed or its name is reused.
//
// The provider is looked up, not created: there's one per account, and it
// belongs to the account's setup (factory-skills#18). The lookup is the same
// as aws-cdk-github-oidc's fromAccount (Apache-2.0), whose role construct
// can't add the conditions above.
import { Aws, CfnOutput, CliCredentialsStackSynthesizer, Duration, Stack, StackProps } from "aws-cdk-lib";
import { Effect, ManagedPolicy, PermissionsBoundary, PolicyDocument, PolicyStatement, Role, WebIdentityPrincipal } from "aws-cdk-lib/aws-iam";
import { Construct } from "constructs";

export const ISSUER = "token.actions.githubusercontent.com";

export interface FactoryApp {
  /** The repo's name, which also names its roles and is its stacks' "project" tag. */
  readonly repo: string;
  /** The repo's immutable numeric ID: gh api repos/OWNER/NAME -q .id */
  readonly id: number;
}

export interface PlatformConfig {
  readonly account: string;
  readonly region: string;
  /** The apps' owner, with its immutable numeric ID: gh api users/NAME -q .id */
  readonly owner: { readonly name: string; readonly id: number };
  /** The repo that holds the reusable workflows, as owner/name. */
  readonly factoryRepo: string;
  /** The permissions boundary every role carries. */
  readonly boundary: string;
  /** The bootstrap qualifier prod deploys through. */
  readonly ciQualifier: string;
  /** The bootstrap qualifier dev stacks deploy through, whose execution role deletes them. */
  readonly devQualifier: string;
  readonly apps: readonly FactoryApp[];
}

export const DEPLOY_WORKFLOW = "app-deploy.yml";
export const CLEANUP_WORKFLOW = "app-dev-cleanup.yml";
export const deployRoleName = (repo: string) => `factory-deploy-${repo}`;
export const cleanupRoleName = (repo: string) => `factory-dev-cleanup-${repo}`;

/** Fails on an app list that would make broken or clashing roles. */
export function validate(config: PlatformConfig): void {
  const seen = new Set<string>();
  for (const app of config.apps) {
    if (!/^[A-Za-z0-9._-]+$/.test(app.repo)) throw new Error(`Not a repo name: "${app.repo}"`);
    if (!Number.isSafeInteger(app.id) || app.id <= 0) throw new Error(`${app.repo}: id must be the repo's numeric ID`);
    if (seen.has(app.repo.toLowerCase())) throw new Error(`${app.repo} is listed twice`);
    seen.add(app.repo.toLowerCase());
    // IAM role names are at most 64 characters.
    if (cleanupRoleName(app.repo).length > 64) throw new Error(`${app.repo}: the name is too long for its role names`);
  }
  if (!/^[0-9]{12}$/.test(config.account)) throw new Error("account must be a 12-digit AWS account ID: pass -c account=<id>, as deploy-roles.sh does");
  if (!Number.isSafeInteger(config.owner.id) || config.owner.id <= 0) throw new Error("owner.id must be the owner's numeric ID");
}

export class GitHubRolesStack extends Stack {
  constructor(scope: Construct, id: string, props: StackProps & { config: PlatformConfig }) {
    const { config, ...stackProps } = props;
    validate(config);
    super(scope, id, {
      stackName: "factory-github-roles",
      description: "GitHub OIDC deploy and dev cleanup roles for factory-built apps. From ErikBean/factory platform/github-oidc.",
      env: { account: config.account, region: config.region },
      terminationProtection: true,
      // Deployed by an admin with their own credentials, not through a CDK
      // bootstrap role, since agents can assume the dev bootstrap's roles.
      synthesizer: new CliCredentialsStackSynthesizer(),
      ...stackProps,
    });

    PermissionsBoundary.of(this).apply(ManagedPolicy.fromManagedPolicyName(this, "Boundary", config.boundary));
    const providerArn = `arn:${Aws.PARTITION}:iam::${Aws.ACCOUNT_ID}:oidc-provider/${ISSUER}`;
    const roleArn = (name: string) => `arn:${Aws.PARTITION}:iam::${Aws.ACCOUNT_ID}:role/${name}`;
    const cfnExecRole = roleArn(`cdk-${config.devQualifier}-cfn-exec-role-${Aws.ACCOUNT_ID}-${Aws.REGION}`);

    // Trusts the app's default branch running the named factory workflow. A
    // push to main has the subject ref:refs/heads/main. A pull_request_target
    // run has the subject pull_request, and its ref claim is the base branch.
    const trust = (app: FactoryApp, workflow: string, event: "push" | "pull_request_target") => {
      const { name: owner, id: ownerId } = config.owner;
      const context = event === "push" ? "ref:refs/heads/main" : "pull_request";
      return new WebIdentityPrincipal(providerArn, {
        StringEquals: {
          [`${ISSUER}:aud`]: "sts.amazonaws.com",
          [`${ISSUER}:repository_id`]: String(app.id),
          [`${ISSUER}:repository_owner_id`]: String(ownerId),
          // The plain and the immutable forms of the subject, since a repo
          // can switch between them.
          [`${ISSUER}:sub`]: [
            `repo:${owner}/${app.repo}:${context}`,
            `repo:${owner}@${ownerId}/${app.repo}@${app.id}:${context}`,
          ],
          ...(event === "pull_request_target" && { [`${ISSUER}:ref`]: "refs/heads/main" }),
        },
        StringLike: {
          [`${ISSUER}:job_workflow_ref`]: `${config.factoryRepo}/.github/workflows/${workflow}@refs/tags/v*`,
        },
      });
    };

    for (const app of config.apps) {
      const deploy = new Role(this, `${app.repo}-deploy`, {
        roleName: deployRoleName(app.repo),
        description: `Deploys ${app.repo} to production from its main branch, through the ${config.ciQualifier} CDK bootstrap.`,
        assumedBy: trust(app, DEPLOY_WORKFLOW, "push"),
        maxSessionDuration: Duration.hours(1),
        inlinePolicies: {
          "assume-cdk-bootstrap-roles": new PolicyDocument({
            statements: [
              new PolicyStatement({
                actions: ["sts:AssumeRole"],
                resources: [roleArn(`cdk-${config.ciQualifier}-*`)],
              }),
            ],
          }),
        },
      });

      const cleanup = new Role(this, `${app.repo}-dev-cleanup`, {
        roleName: cleanupRoleName(app.repo),
        description: `Deletes ${app.repo}'s dev stacks for a branch when its pull request closes.`,
        assumedBy: trust(app, CLEANUP_WORKFLOW, "pull_request_target"),
        maxSessionDuration: Duration.hours(1),
        inlinePolicies: {
          "delete-dev-stacks": new PolicyDocument({
            statements: [
              new PolicyStatement({ sid: "FindStacks", actions: ["cloudformation:DescribeStacks"], resources: ["*"] }),
              new PolicyStatement({
                sid: "DeleteOnlyThisAppsDevStacks",
                actions: ["cloudformation:DeleteStack"],
                resources: [`arn:${Aws.PARTITION}:cloudformation:*:${Aws.ACCOUNT_ID}:stack/*`],
                conditions: {
                  StringEquals: {
                    "aws:ResourceTag/project": app.repo,
                    "aws:ResourceTag/stage": "dev",
                    "cloudformation:RoleArn": cfnExecRole,
                  },
                },
              }),
              new PolicyStatement({
                sid: "DeleteThroughTheCdkExecutionRole",
                effect: Effect.ALLOW,
                actions: ["iam:PassRole"],
                resources: [cfnExecRole],
                conditions: { StringEquals: { "iam:PassedToService": "cloudformation.amazonaws.com" } },
              }),
            ],
          }),
        },
      });

      new CfnOutput(this, `${app.repo}-deploy-arn`.replace(/[^A-Za-z0-9]/g, ""), { value: deploy.roleArn });
      new CfnOutput(this, `${app.repo}-dev-cleanup-arn`.replace(/[^A-Za-z0-9]/g, ""), { value: cleanup.roleArn });
    }
  }
}
