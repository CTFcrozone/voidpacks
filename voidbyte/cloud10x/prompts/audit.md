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
  - "crates/**/*.*"
  - "k8s/**/*.*"
  - ".github/**/*.*"

## Set to false to disable file writing (response below this file's prompt)
write_mode: false

auto_context:
  enabled: false

## Full model names or aliases (see ~/.aipack-base/config-default.toml)
model: flash
```

# TASK

Audit this project against the cloud10x knowledge. Do not modify any file. Report findings only.

## What to review

1. `kdd.yaml` against `kdd.md`: schema, realms, `confirm_delete`, registries, context uniqueness, versions.
2. Manifests against `kubernetes.md`, `lint.md` and `database.md`: security context, probes, resources, ServiceAccounts, NetworkPolicy (both sides, pod ports, DNS), PDBs, Pod Security labels, secrets handling, StatefulSet storage.
3. Dockerfiles against `containers.md` and `parameters.md`: floating or pinned toolchain, base image policy, non-root numeric user, exec-form entrypoint, `--locked`, `.dockerignore`.
4. Cross-file consistency against `contract.md`: names, ports, env vars, image tags, labels, registry and cluster names between `kdd.yaml`, scripts and manifests.
5. Code against the contract: every env var read is set in the manifests; health and readiness endpoints exist and match the probes.
6. Operations: how DB upgrades, backups and rollbacks are handled (`database.md`), and who applies to production (`environments.md`).

## Rules

- Report only what the files show. Quote the file and line. Do not invent issues.
- If something cannot be verified statically (cluster behavior, secret values, image contents), list it under "Not checked".
- Cite the pack file and section that defines each rule.

## Output

Order findings by impact, most impactful first. Use this shape, nothing else:

```
## Findings
1. <file>:<line> - <what is wrong>
   Rule: <pack file, section>
   Fix: <the concrete change>

## Not checked
- <item and why>

## Verified OK
- <short list of areas that match the pack>
```

End with exactly: `./check.sh`

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
