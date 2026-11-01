# Prompts

Tested prompt templates for `pro@coder` with the cloud10x knowledge. These live outside `guide/` and `samples/` on purpose: they are not loaded as knowledge.

## Use

1. Copy a file to `.aipack/.prompt/pro@coder/coder-prompt.md` in your project.
2. Edit the `# PARAMETERS` block and the `model` alias.
3. Commit your tree (prompts with `write_mode: true` change files).
4. Press `r`, then run the commands the prompt ends with.

## Prompts

| File | Purpose | Writes files |
|---|---|---|
| `scaffold-minimal.md` | One Rust service on k3d with KDD, hardened. Smallest end-to-end test. | yes |
| `scaffold-web-db.md` | Web service, PostgreSQL and a db-mgmt Job, hardened, alpine. | yes |
| `add-service.md` | Add one service to an existing project (crate, Dockerfile, manifest, network policy, build/deploy). | yes |
| `add-realm.md` | Add a staging or production realm per `environments.md`. | yes |
| `audit.md` | Read-only review of a project against the pack. Findings only. | no |
| `upgrade-postgres.md` | Runbook for a PostgreSQL major upgrade, using the project's real names. | one doc |

## Conventions

- Parameters first; everything else refers to them by name.
- Every prompt ends with the exact commands to run next.
- Agents write files; a human runs `kdd kapply` and applies to clusters.
- `check.sh` (with `lint.py`) is the gate after every change.
