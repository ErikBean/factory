---
"@favabean/factory-cdk": patch
---

The factory skills take in what building clams-casino's first version taught (#50 to #57, and #8's worktree notes):

- Review checks the rendered `dev` site in a browser and lists a device checklist, which the human runs at ship. Questions settled on a device are asked on their own.
- A review fix that changes behavior goes to the spec writer, then red, then green.
- `tasks.md` names the existing tests each group may change, and red's gate checks that only those changed. Guard and negative tests may pass at red when they're labelled and shown to fail. Green changes no test.
- The spec writer and the releaser check the merged specs with `openspec validate --specs --strict`, and Reasoning lines go after a requirement's scenarios.
- The releaser opens the pull request before archiving, so `(ship)` tasks can record its link.
- The orchestrator watches suite time at every gate, against the new `tdd.suite_budget`.
- The observer records the run's starting request, and its write runs outside a worktree.
- The test writer checks passability in a copy of the repo.

Apps take it by syncing the skills.
