---
---

The dev cleanup role can list stacks: the cleanup workflow finds a branch's dev stacks with `DescribeStacks` and no stack name, which AWS authorizes as `cloudformation:ListStacks`. The admin redeploys the roles from `main`; apps change nothing.
