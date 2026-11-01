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
  - "crates/**/Dockerfile"
  - "k8s/**/*.*"
  - ".github/**/*.*"

## Set to false to disable file writing (response below this file's prompt)
write_mode: false

auto_context:
  enabled: false

## Full model names or aliases (see ~/.aipack-base/config-default.toml)
## Audits reward a stronger model than flash: set one here if you have it configured.
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

- Evidence or silence. Every finding quotes, verbatim, the project lines it is about AND the pack sentence that defines the rule. If you cannot quote both, drop the finding.
- Refute before reporting. For each candidate finding, look for what would make it wrong in the other files and quote what you checked: a NetworkPolicy with an empty `podSelector` selects every pod; a later `kdd kapply` stage in `k3d.sh` applies files not listed in an earlier one; a variable set in a ConfigMap rather than `env:`; a Service port versus the pod port. If the refutation holds, drop the finding.
- Do not re-derive what `check.sh` and `lint.py` already enforce (hardening fields, probes, resources, run labels, image tags, env vars, version, registry). Assume they passed unless the files plainly contradict it. Spend the effort on what they cannot see: design, operations, data safety, missing policies, wrong-but-valid values.
- Report only what the files show. Do not invent issues. Fewer, verified findings beat a long list. "No findings" is a valid result.
- If something cannot be verified statically (cluster behavior, secret values, image contents), list it under "Not checked".
- Line numbers are unreliable from a model: give the file and the quoted text instead.

## Output

Order findings by impact, most impactful first. Use this shape, nothing else:

```
## Findings
1. <file> - <what is wrong>
   Project: "<verbatim quote>"
   Rule: "<verbatim pack sentence>" (<pack file, section>)
   Checked and not refuted: <what you looked for in other files>
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
