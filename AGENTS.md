# Working in this repo

This is the software factory: the platform it runs on, and the library, workflows and roles every app it builds shares. See the [README](README.md) for the layout.

- `openspec/`: requirements as [OpenSpec](https://github.com/Fission-AI/OpenSpec) specs. `specs/` is what must be true now; `changes/` holds proposed changes. Run `npx openspec validate --specs` after changing one, as CI does. (Strict mode also warns about long requirements, which aren't split yet.)
- `platform/aws/`: the AWS account the agents work in, set up once per account by the scripts there, plus [`RUNBOOK.md`](platform/aws/RUNBOOK.md) for steps that can't be automated.
- `platform/client/`: the developer's machine. `platform/github-oidc/` and `platform/github/`: each app's GitHub OIDC roles and the repos' GitHub rules.
- `cdk/`: the construct library apps install from npm. `.github/workflows/app-*.yml`: the reusable workflows apps call by release tag.
- App code lives in each app's own repo, not here.
- **Every pull request adds a change note** in `.changeset/`, as [`.changeset/README.md`](.changeset/README.md) says: `patch`, or `minor` with an **Upgrading** line if apps must act, never `major` before 1.0, or an empty note if nothing is released. Check with `node scripts/check-changeset.mjs main`.
- Releasing: [RELEASING.md](RELEASING.md). Agents open the version-bump PR with `npx changeset version`, and move the apps afterwards; creating and approving the release is the admin's, with `platform/github/release.sh`.

## Research lives elsewhere

The reasoning behind each requirement is in [ErikBean/research](https://github.com/ErikBean/research): findings in `knowledge/tech/aws-agent-guardrails/`, and decisions in `knowledge/projects/aws-agent-bootstrap/`. Specs cite those files by GitHub URL. If a spec or the code changes what's true, update the research there rather than copying it here.

## This repo is public: keep private values out

Never commit:

- AWS account IDs, organization IDs (`o-...`), root IDs (`r-...`), OU IDs (`ou-...`), Identity Center instance or store IDs (`ssoins-...`, `d-...`), or ARNs containing any of these
- Email addresses, names, user names or phone numbers
- Access keys, secrets, tokens, or anything from `~/.aws/`
- Output from commands run against a real account, such as `aws sts get-caller-identity`

Instead:

- In specs, docs and tests, use AWS's documentation placeholders: account IDs `111122223333` and `444455556666`, and `example.com` addresses.
- In code, read real values from the environment, a gitignored local file, or the admin's own profile at deploy time, as `platform/github-oidc/deploy-roles.sh` does. Anything matching `*.local.*`, `.env` or `config.local/` is ignored.

`scripts/check-private.py` scans for these values. It runs in CI on every pull request, and before each commit once hooks are turned on:

```bash
git config core.hooksPath .githooks   # once per clone
python3 scripts/check-private.py      # scan all tracked files
```

If it flags something that isn't private, change the text to a placeholder rather than weakening the check.
