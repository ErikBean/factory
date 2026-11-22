# skills

The factory's agent skills. This was [ErikBean/factory-skills](https://github.com/ErikBean/factory-skills), moved into the factory unchanged apart from paths; its history stays there. `check.sh` lints the repo-setup templates and the factory's workflows and runs `tests/`, and the factory's CI runs it on every pull request.

Agent skills for a multi-agent software factory. You hand an orchestrator agent a feature request. It spawns one sub agent per stage, and each sub agent has one role and uses one skill.

By default the factory uses spec-driven development with [OpenSpec](https://github.com/Fission-AI/OpenSpec) and red-green TDD. Before the build starts, the orchestrator shows you the flow it will run and waits for your yes. You can change the flow per run, or save it in a config file.

## The factory

```text
you ── request ──► factory-orchestrator ── shows the flow, waits for your yes
                          │
                          ▼
   spec ──► [ red ──► green ] for each task group ──► review ──► verify ──► ship
                         ▲                                          │
                         └────────── confirmed blocking findings ───┘
```

| Stage | Agent | Skill | What it does |
| --- | --- | --- | --- |
| spec | `spec-writer` | [`factory-spec-writer`](factory-spec-writer/SKILL.md) | Writes an OpenSpec change: proposal, spec deltas with testable scenarios, design, tasks |
| red | `test-writer` | [`factory-test-writer`](factory-test-writer/SKILL.md) | Writes one failing test per scenario and proves each fails for the right reason |
| green | `implementer` | [`factory-implementer`](factory-implementer/SKILL.md) | Makes the tests pass without touching them, refactors, ticks the tasks |
| review | `reviewer` | [`factory-reviewer`](factory-reviewer/SKILL.md) | Read-only review against the spec, the tests, the diff and any outside requirements in the config |
| verify | `verifier` | [`factory-verifier`](factory-verifier/SKILL.md) | Tries to refute one review finding; blocking findings get three verifiers and survive on two confirmations |
| ship | `releaser` | [`factory-releaser`](factory-releaser/SKILL.md) | Archives the OpenSpec change, then commits, pushes and opens a PR |

Each stage runs as a sub agent with one role and one skill.

The orchestrator itself is [`factory-orchestrator`](factory-orchestrator/SKILL.md). It doesn't trust handoffs: after red it runs the tests to see them fail, and after green it checks they pass and that the red tests weren't edited. Review findings are claims too, so verifiers check each one before it goes back to green, and the orchestrator counts their verdicts by fixed rules. You see what verification removed, and decide the findings the verifiers split on.

By default you're asked at three points: before the build, after the spec, and before ship. A run ends at an open pull request, and merging is yours. The orchestrator won't start a build while `ship.review_queue` factory pull requests, 3 by default, are waiting for your review.

## Install

The skills follow the [Agent Skills](https://agentskills.io) format and don't depend on one agent runtime. The orchestrator spawns each stage with the runtime's own sub agent tool and tells it which skill to use.

There are two places to install them, and they work together:

- **On your machine, for every project.** Link each folder in `skills/` into the shared `~/.agents/skills/` folder, and from there into your agent's folder, such as `~/.claude/skills/`. Link to a clone you keep on `main`, so edits and `git pull` take effect everywhere at once.

  ```bash
  for s in ~/path/to/factory/skills/factory-*/; do
    n=$(basename "$s")
    ln -s "${s%/}" ~/.agents/skills/"$n"
    ln -s ../../.agents/skills/"$n" ~/.claude/skills/"$n"
  done
  ```

- **In each project, pinned.** `factory-repo-setup` copies the stage skills into the project's `.agents/skills/`, links them from `.claude/skills/`, and records the factory commit in `.agents/factory-skills.json`. CI, teammates and cloud sessions then run the version the project was built with. To move a project to a newer version, run `scripts/sync-factory-skills.sh <factory-skills checkout>` in it and commit the result. So the pin doesn't go stale unnoticed, `scripts/check-factory-skills.mjs` says when a pinned skill has changed on factory-skills `main`. The project's CI runs it on every pull request as a warning that doesn't fail the build, and the orchestrator runs it before each build and shows the result in its plan.

In Claude Code, skills in `~/.claude/skills/` take precedence over a project's skills with the same name. With both installed, your machine runs your linked copy and everyone else runs the pinned one.

### Prerequisites in the project being built

- The OpenSpec CLI, set up with `openspec init`. The orchestrator offers to set it up if it's missing.
- A test command the agents can run.
- Git, plus `gh` if you ship as a PR.

## Start a new project

[`factory-repo-setup`](factory-repo-setup/SKILL.md) is the skill to invoke first. Ask for it by name to set up a new app. It walks through the factory's [new-app flow](../README.md#new-apps) in seven steps:

- **You run two admin commands,** one at a time, in your own terminal with your own sign-in. `platform/github/new-app.sh` creates the public repo, adds it to the agents' GitHub App and gives it the rulesets. `platform/github-oidc/deploy-roles.sh` creates its two AWS roles. Agents never hold an admin session.
- **The agent creates the app** from the factory's `template/` with `scripts/create-app.mjs`. That's a `FactoryStack` and `StaticSite` from `@favabean/factory-cdk`, three workflows that call the factory's reusable workflows at a release tag, the merge guard and the pinned skills. Then it opens the setup pull request and the factory's `apps.json` change.
- **It deploys and smoke-tests `dev`**, so you can look before you merge. Merging the setup pull request is the first production deploy.
- **It reports the friction:** your steps and the time to the first production deploy.

After that, use the factory in the new repo. The factory deploys and smoke-tests the branch's `dev` stage and opens a pull request. CI checks it and shows its production diff, merging it deploys to production, and closing it destroys its `dev` stacks.

## Use

In the project you want to build in, ask for something like:

```text
Use the factory to add dark mode with a toggle in the header.
```

The orchestrator restates the request, shows the flow and asks before it starts:

```text
Feature:     Add a dark mode toggle to the header
Change:      openspec change `add-dark-mode` on branch factory/add-dark-mode
Flow:        spec → red → green → review → ship (PR)
TDD:         red-green, one cycle per task group; tests run with `npm test`
Checkpoints: before build (now), after spec, before ship
Config:      defaults (no factory.config.yaml)
```

## Configure

Put a `factory.config.yaml` at the root of the project being built. Every key is optional:

```yaml
workflow:
  spec: openspec        # openspec | none
  tests: red-green      # red-green | tests-with-code | none
tdd:
  batch: group          # group | task | change
confirm:
  before_build: true    # set false to start without asking; the flow is still printed
  after_spec: true
  before_ship: true
ship:
  mode: pr              # pr | commit | none
```

[`references/config.md`](factory-orchestrator/references/config.md) documents every key. Stages hand off to each other in the format in [`references/handoff.md`](factory-orchestrator/references/handoff.md).

## Observe the factory

[`factory-observer`](factory-observer/SKILL.md) takes notes on how factory runs and repo setups go: what worked, what failed, and where an agent or the human hit friction. It writes them as findings and questions in an OKF (Open Knowledge Format) bundle outside the project repo. It never changes the run or the skills. A change it would make to a skill becomes a question for you to decide.

The orchestrator and `factory-repo-setup` spawn it after each stage or step. At the end, it asks you a few retro questions and writes up the run.

It's on while `~/.config/factory/observer.yaml` exists, and you can also ask for it on a single run. Start from [the template](factory-observer/templates/observer.yaml):

```yaml
remote: git@github.com:<you>/research.git  # empty: local bundle in ~/.local/share/factory-observer/
bundle: knowledge
topic: projects/factory-skills
```

With no `remote`, notes go to a local git repo on the machine that ran the factory. With a `remote`, the observer commits to that repo's default branch and pushes. If the repo has an `AGENTS.md`, the observer follows its rules for the bundle.

## Develop

`check.sh` lints the `factory-repo-setup` templates and the factory's workflows with shellcheck, `node --check`, cfn-lint and actionlint, and runs the tests in `tests/`. CI runs it on every pull request, and `main` only takes changes through a pull request that passed it. It needs `node` on the PATH, plus the linters pinned in `skills/tests/requirements.txt`:

```bash
python3 -m venv .venv && .venv/bin/pip install -r skills/tests/requirements.txt   # from the repo root
skills/tests/install-actionlint.sh .venv/bin   # from factory #17
PATH="$PWD/.venv/bin:$PATH" skills/check.sh
```

## Status

This is an early version and hasn't run end to end yet. Expect the skills to change as real runs show what's missing.
