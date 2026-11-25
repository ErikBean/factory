---
---

The dev cleanup role trusts the `pull_request` OIDC subject that `pull_request_target` runs carry, pinned to pull requests into `main` by the `ref` claim. It trusted `ref:refs/heads/main`, so jello-world's first cleanup run couldn't assume it. Fixed by redeploying the roles; apps change nothing.
