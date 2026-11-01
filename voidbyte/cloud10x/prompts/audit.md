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
  - "*/kdd-*.yaml"

## Set to false to disable file writing (response below this file's prompt)
write_mode: false

auto_context:
  enabled: false

## Full model names or aliases (see ~/.aipack-base/config-default.toml)
## flash passes the clean-project audit; lite does not (it mixes up the pack's samples with the project).
## Use a stronger alias here if flash misses real defects.
model: flash
```

# TASK

Audit this project per `audit.md`. Do not modify any file.

End with exactly: `./check.sh`

====
> Write your prompt above the `====` line and below the parametric block (the YAML code block).  
> Press `r` in the terminal to replay this run; the AI response will appear below the `====`.  
> When `write_mode: true`, the file code block will be extracted and saved to the appropriate files.  
