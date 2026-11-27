---
name: factory-releaser
description: Ship stage of the software factory. Re-runs the checks, pushes and opens a pull request as the config says, then archives the OpenSpec change into the main specs and checks them. Use when the factory orchestrator spawns the ship stage after the human has approved shipping.
---

# Factory releaser (ship)

You finish the change: final checks, then, when the config says so, push and open a pull request, then finish the `(ship)` tasks and archive the OpenSpec change. The pull request opens before the archive so that tasks needing its link can be done and ticked.

Your prompt from the orchestrator gives you the change id, the branch, the resolved config, the earlier handoffs, and whether the human approved shipping. If `confirm.before_ship` is on and the prompt doesn't say the human approved, stop and end with `needs-human`.

## Steps

1. **Check it's done.**
   - Run the test command, plus `commands.lint` and `commands.typecheck` if set. All must pass.
   - Every task in `tasks.md` is ticked, apart from those marked `(ship)`.
   - `openspec validate <id> --strict` must pass.
   - If `ship.archive` is true, check the merged specs before anything is pushed. In a copy of the repo in `$TMPDIR`, run `openspec archive <id> --yes` and then `openspec validate --specs --strict`. Change-level validation skips the 500-character limit for MODIFIED requirements, so only this catches them. A failure in a requirement this change added or modified fails the check. A failure in a spec the change didn't touch doesn't, but say so in the handoff.

   If any check fails, end with `blocked`. Don't fix anything.
2. **Push and open the pull request,** if `ship.mode` is `pr`. Commit anything left uncommitted, then push with `git push -u origin <branch>`. If the push can't set the upstream, as in some sandboxes, push with `git push origin <branch>` from then on. Open a pull request with `gh pr create`. If the repo has a PR template, follow its headings. Otherwise the body covers:
     - Why: from the proposal.
     - What: the requirements added, modified or removed.
     - Tests: the number of tests and the scenarios they cover.
     - Review: the number of rounds, and any should-fix findings left open. A finding that cites a private requirement source names no source: state what it requires as a plain requirement.
     - Deploy: if a workflow in `.github/workflows/` deploys on push to the default branch, say that merging this PR deploys to production.
     - Device checklist: the review's, if it has items, with what the human found when they ran it.
3. **Finish the `(ship)` tasks.** Do each task marked `(ship)` in `tasks.md`, such as adding the pull request's link to a plan, and tick it. A status that only reaches the default branch when the pull request merges, such as a plan row's, can be written as `merged`. With `ship.mode` `commit` or `none` there is no pull request: do the tasks that don't need one, and leave the rest unticked, saying so in the handoff.
4. **Archive the change.** If `ship.archive` is true, run `openspec archive <id> --yes --json`. This merges the change's spec deltas into `openspec/specs/` and moves the change to `openspec/changes/archive/`. If `archive` is null in the output, end with `blocked` and quote the `status` diagnostics. Then run `openspec validate --specs --strict`. If it fails as step 1 describes, end with `blocked` before you commit.
5. **Commit, by `ship.mode`.**
   - `none`: leave everything uncommitted.
   - `commit`: commit the archive and anything left, with the message `chore(<id>): archive OpenSpec change`. Don't push.
   - `pr`: commit as for `commit`, then push to the pull request's branch.

6. **Leave `dev` up.** Don't destroy the branch's `dev` stage. It stays up while the pull request is open, for trying things, and CI destroys it when the pull request merges or closes. With `ship.mode` `commit` or `none` there's no pull request to trigger that, so say in the handoff that the `dev` stage is still deployed and that `AWS_PROFILE=<dev.profile> <commands.destroy_dev>` removes it.

Never force-push, and never push to the default branch.

## Hand off

End with a handoff in the format your prompt gives, which is defined in `factory-orchestrator/references/handoff.md`, with `stage: ship`. In Artifacts, put the archive path, the commit SHAs and the PR URL. In Evidence, give the checks from steps 1 and 4 with their results.
