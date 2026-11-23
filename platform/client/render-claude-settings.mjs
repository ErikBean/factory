#!/usr/bin/env node
// Print the Claude Code user settings this machine should have, as JSON.
// Usage: node scripts/render-claude-settings.mjs
// Reads HOME, and finds the SSH private keys in ~/.ssh to deny.
import { createHash } from "node:crypto";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const home = process.env.HOME;

// The AWS CLI names an SSO session's token file after the SHA-1 of the session
// name, so the admin token's file is known before anyone signs in.
const ADMIN_SESSION = "admin";
const adminToken = createHash("sha1").update(ADMIN_SESSION).digest("hex") + ".json";

// Every private key in ~/.ssh: id_* files other than .pub, and any other file
// that starts with a private key header. Matching by name too means a key
// that's already blocked (it reads as empty inside the sandbox) still counts.
function sshPrivateKeys() {
  const dir = join(home, ".ssh");
  let names = [];
  try { names = readdirSync(dir); } catch { return []; }
  return names.filter((n) => {
    if (n.endsWith(".pub")) return false;
    if (n.startsWith("id_")) return true;
    try {
      const head = readFileSync(join(dir, n), "utf8").slice(0, 64);
      return /^-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(head);
    } catch { return false; }
  }).sort().map((n) => `~/.ssh/${n}`);
}

const settings = {
  env: {
    AWS_CONFIG_FILE: join(home, ".aws/agent-config"),
    AWS_PROFILE: "agent-builder",
  },
  permissions: {
    disableBypassPermissionsMode: "disable",
    deny: [
      "Bash(aws configure export-credentials *)",
      "Bash(aws sso get-role-credentials *)",
      "Bash(aws sts get-session-token *)",
    ],
    ask: [
      "Read(~/.aws/**)",
      "Read(~/.ssh/**)",
      "Bash(*.aws/*)",
    ],
  },
  sandbox: {
    enabled: true,
    failIfUnavailable: true,
    allowUnsandboxedCommands: false,
    network: {
      allowedDomains: [
        "*.amazonaws.com",
        "github.com",
        "api.github.com",
        "*.githubusercontent.com",
        "registry.npmjs.org",
      ],
    },
    filesystem: { allowWrite: ["~/.npm"] },
    credentials: {
      files: [
        { path: `~/.aws/sso/cache/${adminToken}`, mode: "deny" },
        ...sshPrivateKeys().map((path) => ({ path, mode: "deny" })),
      ],
      envVars: [{ name: "SSH_AUTH_SOCK", mode: "deny" }],
    },
  },
};

process.stdout.write(JSON.stringify(settings, null, 2) + "\n");
