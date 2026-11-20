// Finds IAM roles and users without a permissions boundary in synthesized
// templates. FactoryStack already fails synth for these, but an app can add
// stacks of its own, and CDK has had roles the boundary context key missed
// (aws/aws-cdk#30179), so CI checks the templates too, before a deploy fails.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

function templates(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return templates(path);
    return name.endsWith(".template.json") ? [path] : [];
  });
}

interface Template {
  Resources?: Record<string, { Type?: string; Properties?: { PermissionsBoundary?: unknown } }>;
}

/** Each role or user without a boundary, as "<template file>: <logical id>". */
export function resourcesWithoutBoundary(cdkOut: string): string[] {
  return templates(cdkOut).flatMap((file) => {
    const { Resources = {} } = JSON.parse(readFileSync(file, "utf8")) as Template;
    return Object.entries(Resources)
      .filter(([, r]) => (r.Type === "AWS::IAM::Role" || r.Type === "AWS::IAM::User") && !r.Properties?.PermissionsBoundary)
      .map(([id]) => `${file}: ${id}`);
  });
}
