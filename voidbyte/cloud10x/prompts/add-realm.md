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
REALM         = staging                   # realm name; also the overlay directory
CONTEXT       = <kubectl context name>    # unique per realm
REGISTRY      = <registry host, no trailing slash>
PROFILE       = none                      # cloud CLI profile, or none
INGRESS_HOST  = <hostname>
REPLICAS      = <number>
CERT_ISSUER   = <cert-manager ClusterIssuer name>
DB_CIDR       = <address range of the managed database>
```

# TASK

Add the realm `REALM` to this project by reproducing `samples/web-db-staging/` with these parameters, following "Realm reference" in `scaffolding.md` and "Adding a realm" in `environments.md`.

End with exactly: `./check.sh REALM`
