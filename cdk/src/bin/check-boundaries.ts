#!/usr/bin/env node
// Fails if any IAM role or user in the synthesized templates has no
// permissions boundary. Run after cdk synth. Usage: factory-check-boundaries [cdk.out]
import { resourcesWithoutBoundary } from "../boundaries";

const missing = resourcesWithoutBoundary(process.argv[2] ?? "cdk.out");
if (missing.length > 0) {
  console.error(`IAM roles or users without a permissions boundary:\n${missing.join("\n")}`);
  process.exit(1);
}
console.log("Every IAM role and user has a permissions boundary.");
