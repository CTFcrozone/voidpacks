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

Follow `database.md` (drop-based upgrades). The runbook uses this project's real names (namespace, StatefulSet, Services, secrets, db-mgmt Job), read from the manifests.

1. Preconditions: backup verified, maintenance window if `DOWNTIME_OK` is no, extension and driver compatibility notes for the target major.
2. Backup: `pg_dump -Fc` (already compressed; no extra gzip) to `BACKUP_STORE`, with a restore test on a throwaway copy before the change.
3. Rehearsal: restore into a scratch StatefulSet at `TO_MAJOR` in a non-production realm; run the application's `/ready` and a smoke query.
4. Cutover steps: scale down writers, final dump, replace the StatefulSet image to the pinned `TO_MAJOR`, restore, run db-mgmt, scale up.
5. Verification checks and expected outputs.
6. Rollback: restore the previous-major dump into a StatefulSet at `FROM_MAJOR`.
7. A manifest diff section that shows only the image tag change the user will apply by hand.

## Rules

- Every command is copy-pasteable with the project's real names.
- Statements that depend on the cluster or data size are marked "measure first".
- If a fact needed for a step is not in the files, list it under "Open questions" instead of guessing.

## Output

- The runbook file only, then a short list of assumptions.

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
