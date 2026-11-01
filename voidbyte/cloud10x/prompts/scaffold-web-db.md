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

## Set to false to disable file writing (response below this file's prompt)
write_mode: true

auto_context:
  enabled: false

## Full model names or aliases (see ~/.aipack-base/config-default.toml)
model: flash
```

# PARAMETERS (edit these; everything below refers to them)

```
SYSTEM        = rust10x
NAMESPACE     = rust10x-web-app
CLUSTER       = cloudapp            # k3d cluster -> context k3d-<CLUSTER>
REG_PORT      = 5000                # registry host k3d-<CLUSTER>-reg.localhost
REALM         = dev_k3d
INGRESS_HOST  = api.rust10x.local
RUST          = latest              # latest | <exact version>
BASE_OS       = alpine
PG_MAJOR      = <number>            # PostgreSQL major, e.g. 18; pinned in the manifests
```

# TASK

Scaffold the web service with PostgreSQL and a db-mgmt Job from the reference `samples/web-db/`, following `scaffolding.md`. Scope is exactly its three workloads: `db`, `db-mgmt`, `web-server`.

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
