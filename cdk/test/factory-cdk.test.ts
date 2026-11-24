// Tests for the factory construct library.
import { App } from "aws-cdk-lib";
import { Annotations, Match, Template } from "aws-cdk-lib/assertions";
import { PermissionsBoundary, Role, ServicePrincipal } from "aws-cdk-lib/aws-iam";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { devSlug, FactoryStack, FunctionUrlSite, functionUrlSiteHandler, StaticSite, stageFromContext } from "../src";

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


describe("FunctionUrlSite", () => {
  test("serves through a public function URL, with no CloudFront or bucket, and its role has the boundary", () => {
    const { template, stack: s } = stack({ stage: "prod" }, (st) => new FunctionUrlSite(st, "Site", { source: siteDir() }));
    template.hasResourceProperties("AWS::Lambda::Url", { AuthType: "NONE" });
    // The same Node.js major as the apps' .nvmrc, which they build and test with.
    template.hasResourceProperties("AWS::Lambda::Function", { Runtime: "nodejs24.x" });
    template.resourceCountIs("AWS::CloudFront::Distribution", 0);
    template.resourceCountIs("AWS::S3::Bucket", 0);
    template.hasResourceProperties("AWS::IAM::Role", { PermissionsBoundary: BOUNDARY });
    template.hasResourceProperties("AWS::Logs::LogGroup", { RetentionInDays: 30 });
    template.hasOutput("UrlSite", {});
    expect(Annotations.fromStack(s).findError("*", Match.anyValue())).toHaveLength(0);
  });

  test("dev keeps its logs for a day", () => {
    const { template } = stack({ stage: "dev", branch: "b" }, (st) => new FunctionUrlSite(st, "Site", { source: siteDir() }));
    template.hasResourceProperties("AWS::Logs::LogGroup", { RetentionInDays: 1 });
  });

  test("the handler serves files with their types, the index for folders, and 404 outside the site", async () => {
    const root = mkdtempSync(join(tmpdir(), "handler-"));
    writeFileSync(join(root, "index.mjs"), functionUrlSiteHandler("home.html"));
    mkdirSync(join(root, "site", "sub"), { recursive: true });
    writeFileSync(join(root, "site", "home.html"), "<h1>home</h1>");
    writeFileSync(join(root, "site", "sub", "home.html"), "<h1>sub</h1>");
    writeFileSync(join(root, "site", "app.webmanifest"), "{}");
    writeFileSync(join(root, "site", "icon.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47]));
    writeFileSync(join(root, "secret.txt"), "outside");
    // Jest can't import an ES module, so a child node process runs the handler.
    const paths = ["/", "/sub/", "/app.webmanifest", "/icon.png", "/missing", "/../secret.txt", "/%2e%2e/secret.txt", "/%zz"];
    const script = `const { handler } = await import(${JSON.stringify(join(root, "index.mjs"))});
      const out = {};
      for (const rawPath of ${JSON.stringify(paths)}) out[rawPath] = await handler({ rawPath });
      console.log(JSON.stringify(out));`;
    const results = JSON.parse(
      execFileSync(process.execPath, ["--input-type=module", "-e", script], { env: { ...process.env, LAMBDA_TASK_ROOT: root }, encoding: "utf8" }),
    );
    const get = async (rawPath: string) => results[rawPath];

    expect(await get("/")).toMatchObject({ statusCode: 200, body: "<h1>home</h1>", headers: { "content-type": "text/html; charset=utf-8" } });
    expect(await get("/sub/")).toMatchObject({ statusCode: 200, body: "<h1>sub</h1>" });
    expect(await get("/app.webmanifest")).toMatchObject({ statusCode: 200, headers: { "content-type": "application/manifest+json" } });
    expect(await get("/icon.png")).toMatchObject({ statusCode: 200, isBase64Encoded: true, body: Buffer.from([0x89, 0x50, 0x4e, 0x47]).toString("base64") });
    for (const path of ["/missing", "/../secret.txt", "/%2e%2e/secret.txt", "/%zz"]) {
      expect(await get(path)).toMatchObject({ statusCode: 404 });
    }
  });
});

describe("package", () => {
  test("the build exports the constructs", () => {
    const built = require("../dist");
    expect(Object.keys(built)).toEqual(
      expect.arrayContaining(["FactoryStack", "StaticSite", "FunctionUrlSite", "stageFromContext", "devSlug", "prodDiffMarkdown", "resourcesWithoutBoundary"]),
    );
  });

  test("aws-cdk-lib is pinned to a minor version, since the boundary check uses its internal _toCloudFormation()", () => {
    const { peerDependencies } = require("../package.json");
    expect(peerDependencies["aws-cdk-lib"]).toMatch(/^~2\.\d+\.\d+$/);
  });
});
