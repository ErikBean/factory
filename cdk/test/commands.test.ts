// Tests for the commands the factory's reusable workflows run from an app's
// installed copy of the library: factory-prod-diff and factory-check-boundaries.
import { App } from "aws-cdk-lib";
import { CfnRole } from "aws-cdk-lib/aws-iam";
import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { FactoryStack, StaticSite } from "../src";

const bin = (name: string) => join(__dirname, "..", "dist", "bin", `${name}.js`);
const run = (name: string, ...args: string[]) => spawnSync("node", [bin(name), ...args], { encoding: "utf8" });

/** Synthesizes a prod app with one StaticSite into a fresh cdk.out folder. */
function synthProd(): string {
  const site = mkdtempSync(join(tmpdir(), "site-"));
  writeFileSync(join(site, "index.html"), "<h1>test</h1>");
  const outdir = mkdtempSync(join(tmpdir(), "cdk-out-"));
  const app = new App({ outdir, context: { stage: "prod", ciQualifier: "ci" } });
  const stack = new FactoryStack(app, "Site", { project: "demo" });
  new StaticSite(stack, "Site", { source: site });
  app.synth();
  return outdir;
}

describe("factory-prod-diff", () => {
  test("with nothing deployed yet, it says there's nothing to compare with", () => {
    const result = run("prod-diff", join(tmpdir(), "no-such-dir"), synthProd());
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("No saved production templates to compare with");
  });

  test("the same templates show no changes", () => {
    const out = synthProd();
    const result = run("prod-diff", out, out);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("No changes to production stacks.");
  });

  test("a resource the pull request adds shows under its template, without color codes", () => {
    const after = synthProd();
    const before = mkdtempSync(join(tmpdir(), "prod-before-"));
    cpSync(after, before, { recursive: true });
    const file = readdirSync(before).find((name) => name.endsWith(".template.json"))!;
    const template = JSON.parse(readFileSync(join(before, file), "utf8"));
    const bucket = Object.keys(template.Resources).find((id) => template.Resources[id].Type === "AWS::S3::Bucket")!;
    delete template.Resources[bucket];
    writeFileSync(join(before, file), JSON.stringify(template));

    const result = run("prod-diff", before, after);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("### Site");
    expect(result.stdout).toContain("AWS::S3::Bucket");
    expect(result.stdout).not.toMatch(/\x1b\[/);
  });

  test("without both folders it prints its usage and exits 2", () => {
    expect(run("prod-diff").status).toBe(2);
  });
});

describe("factory-check-boundaries", () => {
  test("passes a FactoryStack app, including CDK's own helper roles", () => {
    const result = run("check-boundaries", synthProd());
    expect(result.stderr).toBe("");
    expect(result.status).toBe(0);
  });

  test("fails, naming the role, for a stack outside FactoryStack that has a role without the boundary", () => {
    const outdir = mkdtempSync(join(tmpdir(), "cdk-out-"));
    const app = new App({ outdir });
    const { Stack } = require("aws-cdk-lib");
    const other = new Stack(app, "Other");
    new CfnRole(other, "Unbounded", { assumeRolePolicyDocument: {} });
    app.synth();

    const result = run("check-boundaries", outdir);
    expect(result.status).toBe(1);
    expect(result.stderr).toMatch(/Other\.template\.json: Unbounded/);
  });
});
