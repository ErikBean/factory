// The platform's GitHub OIDC roles, from apps.json. Deploy with ./deploy-roles.sh,
// which passes the account from the admin profile as -c account=<id>. The
// account isn't in apps.json, so this public repo names no real account and the
// same app list can be deployed to whichever account the profile signs in to.
import { App } from "aws-cdk-lib";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { GitHubRolesStack, PlatformConfig } from "../src/github-roles-stack";

const app = new App();
const apps = JSON.parse(readFileSync(join(__dirname, "..", "apps.json"), "utf8")) as Omit<PlatformConfig, "account">;
const account = String(app.node.tryGetContext("account") ?? "");
new GitHubRolesStack(app, "GitHubRoles", { config: { ...apps, account } });
