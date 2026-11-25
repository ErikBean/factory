// Tests for the platform's GitHub OIDC roles.
import { App } from "aws-cdk-lib";
import { Template } from "aws-cdk-lib/assertions";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { GitHubRolesStack, ISSUER, PlatformConfig, validate } from "../src/github-roles-stack";

const config: PlatformConfig = {
  account: "111122223333",
  region: "us-east-1",
  owner: { name: "octo", id: 10 },
  factoryRepo: "octo/factory",
  boundary: "agent-boundary",
  ciQualifier: "ci",
  devQualifier: "hnb659fds",
  apps: [
    { repo: "app-one", id: 101 },
    { repo: "app-two", id: 202 },
  ],
};

type Statement = { Condition: Record<string, Record<string, unknown>>; Action: unknown; Resource: unknown; Sid?: string };
type RoleResource = { Properties: Record<string, any> };

function roles(c: PlatformConfig = config): Record<string, RoleResource> {
  const template = Template.fromStack(new GitHubRolesStack(new App(), "Roles", { config: c }));
  const byName: Record<string, RoleResource> = {};
  for (const role of Object.values(template.findResources("AWS::IAM::Role")) as RoleResource[]) {
    byName[role.Properties.RoleName] = role;
  }
  return byName;
}

const trustOf = (role: RoleResource): Statement => {
  const statements = role.Properties.AssumeRolePolicyDocument.Statement;
  expect(statements).toHaveLength(1);
  return statements[0];
};

describe("roles", () => {
  test("each app gets a deploy role and a dev cleanup role, and nothing else", () => {
    expect(Object.keys(roles()).sort()).toEqual([
      "factory-deploy-app-one",
      "factory-deploy-app-two",
      "factory-dev-cleanup-app-one",
      "factory-dev-cleanup-app-two",
    ]);
  });

  test("every role carries the boundary and lasts at most an hour", () => {
    for (const role of Object.values(roles())) {
      expect(JSON.stringify(role.Properties.PermissionsBoundary)).toMatch(/:policy\/agent-boundary"/);
      expect(role.Properties.MaxSessionDuration).toBe(3600);
    }
  });

  test("factory-deploy-app-one trusts only app-one's main branch, pinned by IDs, running the factory's app-deploy.yml at a release tag", () => {
    const { Condition } = trustOf(roles()["factory-deploy-app-one"]);
    expect(Condition).toEqual({
      StringEquals: {
        [`${ISSUER}:aud`]: "sts.amazonaws.com",
        [`${ISSUER}:repository_id`]: "101",
        [`${ISSUER}:repository_owner_id`]: "10",
        [`${ISSUER}:sub`]: ["repo:octo/app-one:ref:refs/heads/main", "repo:octo@10/app-one@101:ref:refs/heads/main"],
      },
      StringLike: { [`${ISSUER}:job_workflow_ref`]: "octo/factory/.github/workflows/app-deploy.yml@refs/tags/v*" },
    });
  });

  // pull_request_target runs have the subject repo:<owner>/<repo>:pull_request,
  // not the branch form, so the base branch is pinned through the ref claim.
  test("factory-dev-cleanup-app-one trusts only app-one's pull requests into main, pinned by IDs, running the factory's app-dev-cleanup.yml at a release tag", () => {
    const { Condition } = trustOf(roles()["factory-dev-cleanup-app-one"]);
    expect(Condition).toEqual({
      StringEquals: {
        [`${ISSUER}:aud`]: "sts.amazonaws.com",
        [`${ISSUER}:repository_id`]: "101",
        [`${ISSUER}:repository_owner_id`]: "10",
        [`${ISSUER}:sub`]: ["repo:octo/app-one:pull_request", "repo:octo@10/app-one@101:pull_request"],
        [`${ISSUER}:ref`]: "refs/heads/main",
      },
      StringLike: { [`${ISSUER}:job_workflow_ref`]: "octo/factory/.github/workflows/app-dev-cleanup.yml@refs/tags/v*" },
    });
  });

  test("no trust policy has a wildcard in its subject, and the only wildcard is the release tag's version", () => {
    for (const role of Object.values(roles())) {
      const { Condition } = trustOf(role);
      expect(JSON.stringify(Condition.StringEquals)).not.toContain("*");
      expect(Object.values(Condition.StringLike)).toEqual([expect.stringMatching(/^octo\/factory\/\.github\/workflows\/[a-z-]+\.yml@refs\/tags\/v\*$/)]);
    }
  });

  test("the deploy role can only assume the ci bootstrap's roles", () => {
    const policies = roles()["factory-deploy-app-one"].Properties.Policies;
    expect(policies).toHaveLength(1);
    const statements: Statement[] = policies[0].PolicyDocument.Statement;
    expect(statements).toHaveLength(1);
    expect(statements[0].Action).toBe("sts:AssumeRole");
    expect(JSON.stringify(statements[0].Resource)).toMatch(/:role\/cdk-ci-\*"/);
  });

  test("the cleanup role deletes only its app's dev stacks, through the dev bootstrap's execution role", () => {
    const policies = roles()["factory-dev-cleanup-app-two"].Properties.Policies;
    const statements: Statement[] = policies[0].PolicyDocument.Statement;
    expect(statements.map((s) => s.Action)).toEqual(["cloudformation:DescribeStacks", "cloudformation:DeleteStack", "iam:PassRole"]);
    const del = statements[1].Condition.StringEquals;
    expect(del["aws:ResourceTag/project"]).toBe("app-two");
    expect(del["aws:ResourceTag/stage"]).toBe("dev");
    expect(JSON.stringify(del["cloudformation:RoleArn"])).toContain("cdk-hnb659fds-cfn-exec-role-");
    expect(JSON.stringify(statements[2].Resource)).toContain("cdk-hnb659fds-cfn-exec-role-");
    expect(statements[2].Condition.StringEquals).toEqual({ "iam:PassedToService": "cloudformation.amazonaws.com" });
  });
});

describe("stack", () => {
  test("is pinned to the account, protected from deletion, and deploys without a bootstrap role", () => {
    const stack = new GitHubRolesStack(new App(), "Roles", { config });
    expect(stack.account).toBe("111122223333");
    expect(stack.terminationProtection).toBe(true);
    const template = Template.fromStack(stack);
    expect(template.toJSON().Parameters?.BootstrapVersion).toBeUndefined();
    template.resourceCountIs("AWS::IAM::OIDCProvider", 0);
    template.resourceCountIs("Custom::AWSCDKOpenIdConnectProvider", 0);
  });

  test("outputs each role's ARN", () => {
    const outputs = Template.fromStack(new GitHubRolesStack(new App(), "Roles", { config })).findOutputs("*");
    expect(Object.keys(outputs)).toHaveLength(4);
  });
});

describe("app list", () => {
  test.each<[string, Partial<PlatformConfig>, RegExp]>([
    ["a repeated repo", { apps: [{ repo: "a", id: 1 }, { repo: "A", id: 2 }] }, /listed twice/],
    ["a name too long for IAM", { apps: [{ repo: "x".repeat(45), id: 1 }] }, /too long/],
    ["a missing repo ID", { apps: [{ repo: "a", id: 0 }] }, /numeric ID/],
    ["a repo name with a slash", { apps: [{ repo: "octo/a", id: 1 }] }, /Not a repo name/],
    ["a bad account", { account: "123" }, /12-digit/],
  ])("rejects %s", (_name, change, error) => {
    expect(() => validate({ ...config, ...change })).toThrow(error);
  });

  test("apps.json is valid with an account passed in, lists jello-world, and names no account itself", () => {
    const real = JSON.parse(readFileSync(join(__dirname, "..", "apps.json"), "utf8"));
    expect(real).not.toHaveProperty("account");
    expect(() => validate({ ...real, account: "111122223333" })).not.toThrow();
    expect(real.apps.map((a: { repo: string }) => a.repo)).toContain("jello-world");
  });
});

describe("which factory refs the roles accept", () => {
  // IAM's StringLike: * matches any run of characters, including none.
  const like = (pattern: string, value: string) =>
    new RegExp(`^${pattern.replace(/[.+?^${}()|[\]\\/]/g, "\\$&").replace(/\*/g, ".*")}$`).test(value);
  const accepted = (ref: string) => {
    const { Condition } = trustOf(roles()["factory-deploy-app-one"]);
    return like(Object.values(Condition.StringLike)[0] as string, `octo/factory/.github/workflows/app-deploy.yml@${ref}`);
  };

  test.each(["refs/tags/v0.2.0", "refs/tags/v1.0.0-rc.1"])("accepts the release tag %s", (ref) => {
    expect(accepted(ref)).toBe(true);
  });

  test.each([
    ["a commit SHA", "3d3c42e5aac5ba805825da76410c181273ba90b1"],
    ["a branch", "refs/heads/main"],
    ["a branch named like a tag", "refs/heads/v0.2.0"],
    ["a tag that isn't a release", "refs/tags/latest"],
  ])("refuses %s", (_name, ref) => {
    expect(accepted(ref)).toBe(false);
  });
});
