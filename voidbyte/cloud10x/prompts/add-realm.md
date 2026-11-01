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
REALM         = <staging | prod | other>
CONTEXT       = <kubectl context name>          # unique per realm
REGISTRY      = <registry host, no trailing slash>
PROFILE       = <cloud CLI profile, or none>
YAML_DIR      = <k8s/<name>/>
MANAGED_DB    = yes | no                        # yes: no in-cluster Postgres in this realm
```

Resolve every value not listed here from `kdd.yaml` and `environments.md`. Never put real account IDs, ARNs or keys in a committed file: use placeholders in `kdd.yaml` and keep real values in the git-ignored overlay `kdd.local.yaml`.

# TASK

Add the realm `REALM` to the existing project, following `environments.md`. Do not touch other realms.

## Files

- `kdd.yaml`: realm `REALM` with `yaml_dir`, `context`, `registry`, `profile` (if any), `confirm_delete: true`. Realm-specific values (replicas, resource sizes, hostnames) as realm variables, not by copying manifests.
- `YAML_DIR`: manifests derived from the existing dev set. Same file names and numbering; differences only through realm variables or files removed because of `MANAGED_DB`.
- Manifests use realm variables (`{{replicas}}`, `{{ingress_host}}`, ...) for everything that differs; add safe defaults to `realms._base_`.
- Production-grade differences per `environments.md`: image reference by digest when the realm requires it, no `latest`, real secrets come from the secret store (no `REPLACE_ME` values applied by hand), TLS terminated at the ingress with a cert issuer reference (no key material in the repo).
- `.gitignore`: add `kdd.local.yaml` if missing.

## Consistency (see contract.md, lint.md)

- The realm context is unique to the realm. `check.sh REALM` must pass.
- A human applies to this realm: do not add any script that applies it unattended.

## Output

- List every file created or changed, every assumption, and every value the user must supply (as a checklist).
- End with exactly: `./check.sh REALM`

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
