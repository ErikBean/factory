// The platform's GitHub OIDC roles, from apps.json. Deploy with ./deploy-roles.sh.
import { App } from "aws-cdk-lib";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { GitHubRolesStack, PlatformConfig } from "../src/github-roles-stack";

const config = JSON.parse(readFileSync(join(__dirname, "..", "apps.json"), "utf8")) as PlatformConfig;
new GitHubRolesStack(new App(), "GitHubRoles", { config });
