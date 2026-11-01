```yaml
#!meta (parametric prompt)

# See .aipack/.prompt/pro@coder/README.md for additional documentation
# Note: All relative paths are relative to the workspace directory (parent folder of .aipack/)

## Static knowledge (relative & absolute)
knowledge_globs:
  - voidbyte@cloud10x/guide/**/*.md
  - voidbyte@cloud10x/samples/**/*.*

## Files the AI will work on (paths & content included in prompt, relative only)
context_globs:
  - "*"
  - "k8s/**/*.*"

## Set to false to disable file writing (response below this file's prompt)
write_mode: true

auto_context:
  enabled: false

## Full model names or aliases (see ~/.aipack-base/config-default.toml)
model: flash
```

# PARAMETERS (edit these; everything below refers to them)

```
FROM_MAJOR   = <current major>
TO_MAJOR     = <target major>
BACKUP_STORE = <where dumps are kept>
DOWNTIME_OK  = yes | no
```

# TASK

Write a runbook for upgrading PostgreSQL from `FROM_MAJOR` to `TO_MAJOR` for this project. Write one file only: `docs/runbooks/postgres-upgrade-<FROM_MAJOR>-to-<TO_MAJOR>.md`. Do not change manifests, images or secrets.

## Content

Instantiate the "Major version upgrade (in-cluster StatefulSet)" section of `database.md` with this project's real names. That section is the procedure: do not invent another, and never propose an in-place image bump on the existing volume (PostgreSQL will not start a new major on an old data directory). Read the names from the manifests: namespace, StatefulSet, Service, PVC (`volumeClaimTemplates` name plus pod ordinal), secrets, db-mgmt Job, web-server Deployment and its replicas.

1. Preconditions: `\du` check, backup location, maintenance window, extension and driver (sqlx) compatibility for `TO_MAJOR`, and the image tag exists. If `DOWNTIME_OK` is `no`, write only the "Open questions" section explaining that this procedure needs downtime, and stop.
2. Backup and verification (dump to `BACKUP_STORE` on the operator machine, `pg_restore -l`, row counts).
3. Rehearsal with a scratch StatefulSet at `TO_MAJOR`, written out as a complete manifest derived from the project's rendered `03-postgres` (new names and labels, same ServiceAccount, own PVC, hardening intact), the restore, the comparison and the cleanup.
4. Cutover, in the order of the section, including deleting the StatefulSet and the PVC and the restore step.
5. Verification with expected outputs.
6. Rollback, including deleting the PVC again.
7. A manifest diff showing only the image tag change, copied from the real line in the project's `03-postgres` (quote it; do not guess it).

## Rules

- Every command is copy-pasteable with the project's real names. Apply manifests with `kdd kapply <stem>`, never `kubectl apply -f` on the source files.
- Secret names and keys, the superuser, the image line and the PVC name are read from the files. If one is not there, list it under "Open questions".
- Statements that depend on the cluster or data size are marked "measure first".
- Do not write commands for steps the section does not contain.

## Output

- The runbook file only, then a short list of assumptions.

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
