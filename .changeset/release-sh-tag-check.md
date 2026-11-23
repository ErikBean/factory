---
"@favabean/factory-cdk": patch
---

`release.sh` no longer takes a missing tag for one at another commit ([#20](https://github.com/ErikBean/factory/pull/20)), and offers to retry the npm approval while npm's automated review is still running, instead of exiting ([#21](https://github.com/ErikBean/factory/pull/21)).
