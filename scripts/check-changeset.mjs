#!/usr/bin/env node
// Checks that a pull request adds a change note in .changeset/, as
// .changeset/README.md describes, and that no note asks for a major version
// before 1.0, which Changesets would release as 1.0.0. CI runs it on every
// pull request; run it yourself before opening one.
//
// Usage: node scripts/check-changeset.mjs [base]
//
// base defaults to HEAD^1, the base branch's side of the merge commit CI
// checks out (with fetch-depth 2). Locally, pass main.
//
// The version-bump pull request, which consumes the notes and changes
// cdk/package.json's version, needs none. Dependabot's pull requests pass with
// a warning: the release's version-bump pull request covers them in a note.
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const base = process.argv[2] ?? "HEAD^1";
const pkg = JSON.parse(readFileSync("cdk/package.json", "utf8"));
const fail = (msg) => {
  console.error(`::error title=Change note::${msg.replace(/\n/g, "%0A")}`);
  process.exit(1);
};

const diff = execFileSync("git", ["diff", "--name-status", "--no-renames", base, "HEAD"], { encoding: "utf8" })
  .trim()
  .split("\n")
  .filter(Boolean)
  .map((line) => line.split("\t"));
const isNote = (path) => /^\.changeset\/[^/]+\.md$/.test(path) && path !== ".changeset/README.md";
const added = diff.filter(([status, path]) => status === "A" && isNote(path)).map(([, path]) => path);
const notes = diff.filter(([status, path]) => (status === "A" || status === "M") && isNote(path)).map(([, path]) => path);
const consumed = diff.some(([status, path]) => status === "D" && isNote(path));
const versionChanged = diff.some(([, path]) => path === "cdk/package.json") &&
  JSON.parse(execFileSync("git", ["show", `${base}:cdk/package.json`], { encoding: "utf8" })).version !== pkg.version;

for (const path of notes) {
  const text = readFileSync(path, "utf8");
  const match = text.match(/^---\n([\s\S]*?)\n?---\n([\s\S]*)$/);
  if (!match) fail(`${path} needs front matter between two --- lines. See .changeset/README.md.`);
  const [, front, body] = match;
  if (!body.trim()) fail(`${path} needs a line saying what changed, below its front matter.`);
  for (const line of front.split("\n").filter((l) => l.trim())) {
    const entry = line.match(/^\s*["']?([^"':]+)["']?\s*:\s*(\w+)\s*$/);
    if (!entry) fail(`${path}: can't read "${line}". Write "${pkg.name}": patch or minor.`);
    const [, name, bump] = entry;
    if (name !== pkg.name) fail(`${path} names ${name}: notes name ${pkg.name}, which stands for the whole release.`);
    if (!["patch", "minor", "major"].includes(bump)) fail(`${path}: "${bump}" isn't patch, minor or major.`);
    if (bump === "major" && pkg.version.startsWith("0.")) {
      fail(`${path} asks for major, which would release 1.0.0. Before 1.0, use minor for changes apps must act on, with an Upgrading line.`);
    }
  }
}

if (added.length) {
  console.log(`Change notes: ${added.join(", ")}`);
} else if (consumed && versionChanged) {
  console.log(`The version-bump pull request for ${pkg.version}: it consumes the notes, so it needs none.`);
} else if (process.env.PR_AUTHOR === "dependabot[bot]") {
  console.log("::warning title=Change note::Dependabot's pull request has no change note. The next version-bump pull request adds one covering Dependabot's updates.");
} else {
  fail(
    "This pull request adds no change note in .changeset/. Add one as .changeset/README.md says: " +
      "patch, or minor if apps must act, or an empty note if the change releases nothing.",
  );
}
