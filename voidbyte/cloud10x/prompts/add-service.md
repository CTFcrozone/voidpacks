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
BLOCK         = <new-service>       # kebab-case; used for the block, manifest, image, crate dir and pod label
PORT          = <pod port>
NEEDS_DB      = yes | no
EXPOSED       = yes | no            # ingress route needed
INGRESS_PATH  = <path>              # if EXPOSED
```

Resolve every value not listed here from the existing project, then `parameters.md`. Never copy names from samples.

# TASK

Add the service `BLOCK` to this project per `services.md`.

End with exactly: `cargo generate-lockfile && cargo clippy --workspace --locked --all-targets -- -D warnings && ./check.sh && ./k3d.sh build && ./k3d.sh deploy`

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
