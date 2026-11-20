# factory

The software factory in one repo: the platform it runs on, the CDK constructs and
workflows every app it builds shares, and the agents' skills. The goal is to
spin up a new web app with as few human steps as possible, behind guardrails
against surprise costs and security risks.

| Folder | What | State |
| --- | --- | --- |
| `cdk/` | `@favabean/factory-cdk`, the construct library apps install from npm | Started |
| `workflows/` | Reusable GitHub Actions workflows that apps call by SHA | Planned |
| `platform/` | Account setup, permissions boundary, OIDC deploy roles, the agents' GitHub token hook (from aws-agent-bootstrap, dev-machine and agent-github) | Planned |
| `skills/` | The factory's agent skills (from factory-skills) | Planned |
| `template/` | The starting point for a new app | Planned |

## cdk

- **`FactoryStack`**: the base stack for every app. It reads the stage
  (`-c stage=dev|preview|prod`) and names stacks per branch or pull request. It
  deploys preview and prod through the separate ci bootstrap and adds the
  `project`, `stage` and `branch` tags the cleanup workflows find stacks by. It
  puts the account's permissions boundary on every role, and fails synth if any
  role or user goes without it. Dev and preview stacks delete their data when
  destroyed.
- **`StaticSite`**: a private S3 bucket served through CloudFront with origin
  access control, filled from a local folder on every deploy.
- **`factory-dev-slug <branch>`**: prints the slug dev stacks are named and
  tagged with, so workflows don't keep their own copy of the rule.

An app's whole CDK code:

```ts
import { App } from "aws-cdk-lib";
import { FactoryStack, StaticSite } from "@favabean/factory-cdk";

const app = new App();
const stack = new FactoryStack(app, "Site", { project: "jello-world" });
new StaticSite(stack, "Site", { source: "site" });
```

`aws-cdk-lib` is a peer dependency pinned to one minor version. The boundary
check reads CDK internals, because CDK attaches the boundary to some of its own
helper roles as a raw override. Raise the pin on purpose, with the tests.

```sh
npm install
npm test      # type-check, build, then jest
```

## License

[Apache-2.0](LICENSE).
