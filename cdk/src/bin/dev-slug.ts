#!/usr/bin/env node
// Prints the dev slug for a branch, as FactoryStack names and tags its dev
// stacks, so workflows such as the dev cleanup find them without keeping a
// shell copy of devSlug in step. Usage: factory-dev-slug <branch>
import { devSlug } from "../stage";

const branch = process.argv[2];
if (!branch) {
  console.error("Usage: factory-dev-slug <branch>");
  process.exit(2);
}
process.stdout.write(devSlug(branch));
