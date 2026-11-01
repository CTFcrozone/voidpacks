# Prompts

Prompt templates for `pro@coder` with the cloud10x knowledge. The reference projects and checks they rely on are tested; model output is verified by `check.sh`, not assumed. These live outside `guide/` and `samples/` on purpose: they are not loaded as knowledge.

## Use

1. Copy a file to `.aipack/.prompt/pro@coder/coder-prompt.md` in your project.
2. Edit the `# PARAMETERS` block and the `model` alias.
3. Commit your tree (prompts with `write_mode: true` change files).
4. Press `r`, then run the commands the prompt ends with.

## Prompts

| File | Purpose | Writes files |
|---|---|---|
| `scaffold-minimal.md` | Reproduces the verified reference `samples/minimal/` (one hardened Rust service on k3d with KDD) with your parameters. | yes |
| `scaffold-web-db.md` | Reproduces the reference `samples/web-db/` (web service, PostgreSQL, db-mgmt Job, hardened, alpine) with your parameters. | yes |
| `add-service.md` | Add one service to an existing project (crate, Dockerfile, manifest, network policy, build/deploy). | yes |
| `add-realm.md` | Adds a managed-database realm (overlay + manifests) by reproducing `samples/web-db-staging/` with your parameters. | yes |
| `audit.md` | Read-only review of a project against the pack. Findings only. | no |
| `upgrade-postgres.md` | Runbook for a PostgreSQL major upgrade, using the project's real names. | one doc |

Zed users: `../editors/zed/` has snippets that insert each prompt's parameters and task.

## Check a scaffold against its reference

A scaffold prompt reproduces a reference project, so the result can be diffed. In the new project, with `P=~/.aipack-base/pack/installed/voidbyte/cloud10x`:

```sh
diff -r . $P/samples/web-db -x .git -x .aipack -x README.md -x check.sh -x lint.py -x Cargo.lock -x target
```

(`samples/minimal` for the minimal scaffold.) With the reference's example parameters the only difference is the `.aipack/` line in `.gitignore`. With other parameters the differences are exactly the mapped values (`scaffolding.md`); anything else is drift. Then copy the checker, run the gates:

```sh
cp $P/samples/web-app/check.sh $P/samples/web-app/lint.py . && chmod +x check.sh
cargo generate-lockfile && ./k3d.sh up && ./check.sh && ./k3d.sh build && ./k3d.sh deploy
```

A realm prompt is checked the same way. In the project, after the run:

```sh
diff -r staging $P/samples/web-db-staging/staging
diff -r k8s/staging $P/samples/web-db-staging/k8s/staging
git diff kdd.yaml     # exactly one added line under overlays:
```

With the reference parameters (`staging`, `staging-example`, ...) and a project named like the reference, both diffs are empty. Otherwise the differences are exactly the mapped values and the project's own names.

## Conventions

- Parameters first; everything else refers to them by name.
- Every prompt ends with the exact commands to run next.
- Agents write files; a human runs `kdd kapply` and applies to clusters.
- `check.sh` (with `lint.py`) is the gate after every change.
