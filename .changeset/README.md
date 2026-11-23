# Change notes

Every pull request adds one note here, a Markdown file that says how the change should be released and what to tell apps. `scripts/check-changeset.mjs` fails a pull request without one. [RELEASING.md](../RELEASING.md) says how the notes become a release.

```markdown
---
"@favabean/factory-cdk": patch
---

What changed, for someone maintaining an app. Link the pull request.

**Upgrading:** what an app must do, only for a `minor` note.
```

The package name stands for the whole factory release: the workflows, the library, the specs, the skills and the template share one version.

Choose the bump for what apps have to do, while the version is below 1.0:

- **`minor`** when an app must change something to take the release: say what under **Upgrading**.
- **`patch`** for everything else, new features included.
- **Never `major`** before 1.0: Changesets would release 1.0.0. CI refuses it.

A change that releases nothing, such as to CI or this repo's docs, adds an empty note: front matter with no packages (`---` twice) and a line saying why.
