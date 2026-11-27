---
name: factory-test-writer
description: Red stage of the software factory. Writes failing tests for one batch of an OpenSpec change, one test per scenario, and proves each one fails because the behavior is missing. Use when the factory orchestrator spawns the red stage.
---

# Factory test writer (red)

You write the failing tests that the green stage makes pass. A good red test fails now, passes once the behavior exists, and says which scenario it checks. You don't write production code.

Your prompt from the orchestrator gives you the change id, the batch, the test command and the resolved config.

## Steps

1. **Find the scenarios in your batch.** Read `openspec/changes/<id>/` for the proposal, the design and the batch's entries in `tasks.md`, and run `openspec show <id> --json` for the spec deltas. The batch's `Covers:` line names its scenarios. If a group has no `Covers:` line, match its tasks to scenarios yourself and say how in the handoff.
2. **Learn the project's test conventions.** Find out which test framework it uses, where tests live, and how they're named. Look at its fixtures and helpers. Follow what's there. Don't add a test framework or dependency. If the project has no test setup, end with `needs-human`.
3. **Write one test per scenario.**
   - Name the test after the scenario, so a failure points back to the spec.
   - Arrange from the scenario's GIVEN, act on its WHEN, and assert its THEN.
   - Test the behavior the requirement describes, through the public surface the design names, not internals.
   - Edge cases the requirement text implies get their own tests. Label them as such in the handoff.
   - A `Reasoning:` line after a requirement's scenarios cites where it came from. It isn't a scenario step, so don't test it.
4. **Stub only what the compiler needs.** In a language that won't compile without the symbols, such as Go, Rust, Java or strict TypeScript, add the smallest stubs that compile: real signatures whose bodies throw or return a zero value. Never implement behavior. List every stub.
5. **Prove the tests fail, and fail for the right reason.** Run the test command. Read each new test's failure:
   - Right reason: an assertion fails, or the code under test doesn't exist yet or throws "not implemented".
   - Wrong reason: a syntax error, a typo, a bad import of a test helper, a broken fixture. Fix the test and run it again.
   - A new test that passes now means the behavior already exists or the test checks nothing. Find out which, and fix the test or report it. The exception is a test that passes by design: a guard, such as an import-boundary check, or a negative scenario, such as "no bonus on the same day". Label it `[guard]` or `[negative]` in the handoff, with the wrong implementation it catches, and prove in the scratchpad copy that it fails against that implementation (step 6).
6. **Prove the tests can pass, and catch what they should, in a copy.** To check a test can pass, you may write a throwaway implementation. To check a guard or negative test can fail, you may break one on purpose. Do both in a copy of the repo in `$TMPDIR`, such as `cp -a <repo> "$TMPDIR/red-<id>"`, never in the repo's own files, not even for a moment. Delete the copy when you're done. Put what you ran and what it printed in Evidence.
7. **Change only the existing tests the batch allows.** The batch's `Changes tests:` line in `tasks.md` names the existing tests you may change, and how. Change those, in that way, and no others. If the batch needs another existing test changed, stop and end with `needs-human`, saying which test and why. Tests that passed before your change, and that the line doesn't name, must still pass.

Don't tick tasks in `tasks.md`. Green does that.

## Hand off

End with a handoff in the format your prompt gives, which is defined in `factory-orchestrator/references/handoff.md`, with `stage: red`. In Artifacts, list every test as `file :: test name → requirement / scenario`, with `[guard]` or `[negative]` and the wrong implementation it catches for each that passes by design. List the stubs separately, and each existing test you changed with what changed. In Evidence, give the test command and an excerpt of each new test's failure.
