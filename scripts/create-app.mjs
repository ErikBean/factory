#!/usr/bin/env node
// Sets up a new factory-built app from template/, into a clone of its repo.
// The agent runs this after platform/github/new-app.sh has made the repo.
//
//   node scripts/create-app.mjs <clone of the new repo> <name> [--skip-skills]
//
// It copies the template's tracked files (never untracked ones), fills in the
// placeholders and syncs the factory's stage skills from this checkout. The
// app pins this checkout's release: the workflows call the factory at
// v<version> and package.json depends on ^<version>, where <version> is
// cdk/package.json's, so run it from a checkout of the release to pin, such
// as `git checkout v0.3.0`.
//
// Placeholders: {{name}} the repo and project name, {{stack}} the stack's
// construct id, {{owner}} the GitHub owner and {{factory}} the factory repo
// (both from platform/github-oidc/apps.json), {{release}} and {{version}}.
import { execFileSync } from "node:child_process";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const factory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const skipSkills = args.includes("--skip-skills");
const [target, name] = args.filter((a) => !a.startsWith("--"));

function fail(message) {
  console.error(message);
  process.exit(2);
}
if (!target || !name) fail("usage: node scripts/create-app.mjs <clone of the new repo> <name> [--skip-skills]");
// A stack name must start with a letter, and the name also tags stacks and
// names the app's IAM roles, so keep it plain.
if (!/^[a-z][a-z0-9-]{0,43}$/.test(name)) fail(`"${name}": use lowercase letters, digits and hyphens, starting with a letter, at most 44 characters`);
if (!existsSync(join(target, ".git"))) fail(`${target} isn't a git clone: clone the new repo first`);
if (existsSync(join(target, "package.json"))) fail(`${target} already has a package.json: this sets up a new repo only`);

const apps = JSON.parse(readFileSync(join(factory, "platform/github-oidc/apps.json"), "utf8"));
const version = JSON.parse(readFileSync(join(factory, "cdk/package.json"), "utf8")).version;
const values = {
  name,
  stack: name.split("-").map((w) => w.charAt(0).toUpperCase() + w.slice(1)).join("") + "Stack",
  owner: apps.owner.name,
  factory: apps.factoryRepo,
  release: `v${version}`,
  version,
};

// git ls-files -s: "<mode> <object> <stage>\t<path>", NUL-separated.
const tracked = execFileSync("git", ["-C", factory, "ls-files", "-s", "-z", "template"], { encoding: "utf8" })
  .split("\0")
  .filter(Boolean)
  .map((line) => {
    const [meta, path] = line.split("\t");
    return { mode: meta.split(" ")[0], path };
  });
if (tracked.length === 0) fail("template/ has no tracked files: run this from a factory checkout");

const left = [];
for (const { mode, path } of tracked) {
  const rel = path.slice("template/".length);
  const text = readFileSync(join(factory, path), "utf8").replace(/\{\{(\w+)\}\}/g, (m, key) => {
    if (!(key in values)) left.push(`${rel}: ${m}`);
    return values[key] ?? m;
  });
  const out = join(target, rel);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, text);
  if (mode === "100755") chmodSync(out, 0o755);
}
if (left.length) fail(`Unknown placeholders:\n${left.join("\n")}`);
console.log(`Copied ${tracked.length} files for ${name}, pinned to ${apps.factoryRepo} ${values.release}`);

if (skipSkills) {
  console.log("Skipped the skills: run scripts/sync-factory-skills.sh <factory checkout> in the app later.");
} else {
  try {
    execFileSync(join(target, "scripts/sync-factory-skills.sh"), [factory], { cwd: target, stdio: "inherit" });
  } catch {
    // In a Claude Code sandbox, writing .claude/skills is refused (factory#7).
    console.error("Syncing the skills failed. Outside the agent sandbox, run in the app:");
    console.error(`  scripts/sync-factory-skills.sh ${factory}`);
    process.exit(1);
  }
}

console.log(`
Next, in ${target}:
  npm install && npm test && npx cdk synth --quiet -c stage=prod
  git add -A && git commit, then open the setup pull request.
And in the factory: add {"repo": "${name}", "id": <the repo's ID>} to platform/github-oidc/apps.json.`);
