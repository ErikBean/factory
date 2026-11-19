#!/usr/bin/env node
// Prints, as Markdown, how this checkout's prod stage differs from the last
// production deploy's templates. Usage: factory-prod-diff <before dir> <after dir>
import { prodDiffMarkdown } from "../prod-diff";

const [before, after] = process.argv.slice(2);
if (!before || !after) {
  console.error("Usage: factory-prod-diff <last deployed templates dir> <cdk.out dir>");
  process.exit(2);
}
console.log(prodDiffMarkdown(before, after));
