---
"@favabean/factory-cdk": patch
---

Adds a `research` key to `factory.config.yaml`: where an app's research lives, as a folder in a knowledge bundle. The spec stage reads it and proposes requirements from its recommendations, each citing its source; the orchestrator lists them at the spec review, where the human decides; and the reviewer checks the code follows them. The template and `factory-repo-setup` ask for it. Apps that don't set it are unaffected.
