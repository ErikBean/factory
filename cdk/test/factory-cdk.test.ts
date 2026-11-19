// Tests for the factory construct library.
import { App } from "aws-cdk-lib";
import { Annotations, Match, Template } from "aws-cdk-lib/assertions";
import { PermissionsBoundary, Role, ServicePrincipal } from "aws-cdk-lib/aws-iam";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { devSlug, FactoryStack, StaticSite, stageFromContext } from "../src";

const BOUNDARY = { "Fn::Join": ["", Match.arrayWith([Match.stringLikeRegexp(":policy/agent-boundary$")])] };

function siteDir(): string {
  const dir = mkdtempSync(join(tmpdir(), "site-"));
  writeFileSync(join(dir, "index.html"), "<h1>test</h1>");
  return dir;
}

function stack(context: Record<string, string>, build?: (s: FactoryStack) => void) {
  const app = new App({ context: { ciQualifier: "ci", ...context } });
  const s = new FactoryStack(app, "TestStack", { project: "demo" });
  build?.(s);
  return { app, stack: s, template: Template.fromStack(s) };
}

describe("stage", () => {
  test("prod has no suffix, keeps its data and uses the ci qualifier", () => {
    const stage = stageFromContext(new App({ context: { stage: "prod", ciQualifier: "ci" } }));
    expect(stage).toEqual({ name: "prod", suffix: "", ephemeral: false, qualifier: "ci" });
  });

  test("dev is named per branch and ephemeral", () => {
    const stage = stageFromContext(new App({ context: { stage: "dev", branch: "factory/add-site" } }));
    expect(stage.suffix).toMatch(/^-dev-factory-add-site-[0-9a-f]{8}$/);
    expect(stage.ephemeral).toBe(true);
    expect(stage.qualifier).toBeUndefined();
  });

  test.each(["prod", "preview"])("%s fails without the ci qualifier", (name) => {
    expect(() => stageFromContext(new App({ context: { stage: name, pr: "12" } }))).toThrow(/ci bootstrap/);
  });

  test("a missing stage fails", () => {
    expect(() => stageFromContext(new App())).toThrow(/Pass the stage/);
  });

  const branches = ["factory/add-site", "feature/a", "feature-a", "feature_a", "--weird--/", "日本",
    `factory/${"x".repeat(60)}-one`, `factory/${"x".repeat(60)}-two`];

  test("branches that read the same get different dev slugs", () => {
    expect(new Set(branches.map(devSlug)).size).toBe(branches.length);
  });

  test("the factory-dev-slug command prints devSlug", () => {
    const bin = join(__dirname, "..", "dist", "bin", "dev-slug.js");
    for (const branch of branches) {
      expect(execFileSync("node", [bin, branch]).toString()).toBe(devSlug(branch));
    }
  });
});

describe("FactoryStack", () => {
  test("names, tags and bootstrap follow the stage", () => {
    const prod = stack({ stage: "prod" }).app.synth().getStackByName("demo");
    expect(prod.tags).toEqual({ project: "demo", stage: "prod" });
    expect(prod.assumeRoleArn).toContain("cdk-ci-deploy-role");

    const dev = stack({ stage: "dev", branch: "b" }).app.synth().getStackByName(`demo-dev-${devSlug("b")}`);
    expect(dev.tags).toEqual({ project: "demo", stage: "dev", branch: devSlug("b") });
    expect(dev.assumeRoleArn).toContain("cdk-hnb659fds-deploy-role");
  });

  test("every role the app creates gets the boundary", () => {
    const { template } = stack({ stage: "prod" }, (s) => {
      new Role(s, "AppRole", { assumedBy: new ServicePrincipal("lambda.amazonaws.com") });
    });
    template.hasResourceProperties("AWS::IAM::Role", { PermissionsBoundary: BOUNDARY });
  });

  test("a role that escapes the boundary fails synth", () => {
    const { stack: s } = stack({ stage: "prod" }, (st) => {
      const role = new Role(st, "Escapee", { assumedBy: new ServicePrincipal("lambda.amazonaws.com") });
      PermissionsBoundary.of(role).clear();
    });
    const errors = Annotations.fromStack(s).findError("*", Match.stringLikeRegexp("permissions boundary"));
    expect(errors).toHaveLength(1);
  });
});

describe("StaticSite", () => {
  test("prod keeps the bucket; every role, including CDK's own helpers, has the boundary", () => {
    const { template, stack: s } = stack({ stage: "prod" }, (st) => new StaticSite(st, "Site", { source: siteDir() }));
    template.hasResource("AWS::S3::Bucket", { DeletionPolicy: "Retain" });
    template.hasResourceProperties("AWS::S3::Bucket", {
      PublicAccessBlockConfiguration: { BlockPublicAcls: true, BlockPublicPolicy: true, IgnorePublicAcls: true, RestrictPublicBuckets: true },
    });
    template.resourceCountIs("AWS::CloudFront::OriginAccessControl", 1);
    const roles = template.findResources("AWS::IAM::Role");
    expect(Object.keys(roles).length).toBeGreaterThan(0);
    for (const role of Object.values(roles)) expect(role.Properties.PermissionsBoundary).toBeDefined();
    expect(Annotations.fromStack(s).findError("*", Match.anyValue())).toHaveLength(0);
    template.hasOutput("UrlSite", {});
  });

  test("dev deletes the bucket and its objects with the stack", () => {
    const { template } = stack({ stage: "dev", branch: "b" }, (st) => new StaticSite(st, "Site", { source: siteDir() }));
    template.hasResource("AWS::S3::Bucket", { DeletionPolicy: "Delete" });
    template.resourceCountIs("Custom::S3AutoDeleteObjects", 1);
  });
});


describe("package", () => {
  test("the build exports the constructs", () => {
    const built = require("../dist");
    expect(Object.keys(built)).toEqual(
      expect.arrayContaining(["FactoryStack", "StaticSite", "stageFromContext", "devSlug", "prodDiffMarkdown", "resourcesWithoutBoundary"]),
    );
  });

  test("aws-cdk-lib is pinned to a minor version, since the boundary check uses its internal _toCloudFormation()", () => {
    const { peerDependencies } = require("../package.json");
    expect(peerDependencies["aws-cdk-lib"]).toMatch(/^~2\.\d+\.\d+$/);
  });
});
