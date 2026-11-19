// How a pull request's prod stage differs from the templates the last
// production deploy saved, as Markdown for the job summary. It needs no AWS
// credentials, so pull request CI can run it. It shows added, removed and
// changed resources, but not drift, and not reliably whether a change replaces
// a resource.
import { formatDifferences, fullDiff } from "@aws-cdk/cloudformation-diff";
import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { Writable } from "node:stream";

function templatesIn(dir: string): string[] {
  return existsSync(dir) ? readdirSync(dir).filter((name) => name.endsWith(".template.json")) : [];
}

function read(dir: string, name: string): object {
  return JSON.parse(readFileSync(join(dir, name), "utf8"));
}

/**
 * Compares every template in `before` (the last deploy's) with `after` (this
 * checkout's synth). A missing or empty `before` means nothing to compare with.
 */
export function prodDiffMarkdown(before: string, after: string): string {
  const out = ["## Production changes", ""];
  const old = templatesIn(before);
  if (old.length === 0) {
    out.push("No saved production templates to compare with. The first deploy, or one more than 90 days ago, saves them.");
    return out.join("\n");
  }
  const current = templatesIn(after);
  let changed = 0;
  for (const name of [...new Set([...old, ...current])].sort()) {
    const diff = fullDiff(old.includes(name) ? read(before, name) : {}, current.includes(name) ? read(after, name) : {});
    if (diff.isEmpty) continue;
    changed++;
    let text = "";
    const stream = new Writable({
      write(chunk, _encoding, done) {
        text += chunk;
        done();
      },
    });
    formatDifferences(stream, diff);
    // The formatter colors its output; the job summary shows plain text.
    const plain = text.replace(/\x1b\[[0-9;]*m/g, "").trim();
    out.push(`### ${name.replace(/\.template\.json$/, "")}`, "", "```", plain, "```", "");
  }
  if (changed === 0) out.push("No changes to production stacks.");
  return out.join("\n");
}
