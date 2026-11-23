---
"@favabean/factory-cdk": patch
---

Releases are now made from change notes: each pull request adds one in `.changeset/`, CI requires it, and `npx changeset version` writes the version and `cdk/CHANGELOG.md`, where versions after 0.3.0 are recorded. Before 1.0, a minor version means apps must act, and a patch is everything else. The template's skills check now compares an app's pin with the factory's latest release rather than its `main` branch, so unreleased skill changes no longer show as "behind".
