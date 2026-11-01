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

The procedure is the "Major version upgrade (in-cluster StatefulSet)" section of `database.md`: its variables block and phases A, B and C. Copy them into the runbook **verbatim**, changing only the values in the variables block. Do not paraphrase a phase into prose, drop `set -euo pipefail`, reorder steps, or add an in-place image bump on the existing volume (PostgreSQL will not start a new major on an old data directory). Read the values from the project's manifests: namespace, system, StatefulSet, PVC (`volumeClaimTemplates` name + StatefulSet + `-0`), web-server Deployment, db-mgmt Job, rendered output folder, the realm's source folder.

Runbook sections, in order:

1. Parameters and context (the real names, `BACKUP_STORE` as `DUMP`).
2. Preconditions: the two commands from `database.md` with the real names, the maintenance window, extension and driver (sqlx) compatibility for `TO_MAJOR`. If `DOWNTIME_OK` is `no`, write only "Open questions" explaining that this procedure needs downtime, and stop.
3. How to run (save the variables block and each phase as files, run with `bash -c 'source vars.sh; source phaseX.sh'`, never paste a phase into an interactive shell; commit the image change only after the cutover is verified), then the Variables block, Phase A, Phase B and Phase C, each in its own code block with a one-line purpose.
4. Verification after phase B: `/health` and `/ready` return `200 OK` with body `ok` (use the project's ingress host), plus one business request.
5. Manifest change: quote the real `image:` line from the project's `03-postgres` manifest and the line it becomes (`FROM_MAJOR` replaced by `TO_MAJOR`, same variant). Phase B applies this edit with `sed`; say so.
6. Open questions and assumptions.

## Rules

- Secret names and keys, the superuser, the image line and the PVC name are read from the files. If one is not there, list it under "Open questions".
- Statements that depend on the cluster or data size are marked "measure first".
- Do not write commands the section does not contain.

## Output

- The runbook file only, then a short list of assumptions.

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
