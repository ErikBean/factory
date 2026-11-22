import { App } from "aws-cdk-lib";
import { FactoryStack, StaticSite } from "@favabean/factory-cdk";

/** {{name}}: one static site to start from. The stage, names, tags and guardrails come from FactoryStack. */
export function buildApp(app: App): void {
  const stack = new FactoryStack(app, "{{stack}}", { project: "{{name}}" });
  new StaticSite(stack, "Site", { source: "site" });
}
