#!/usr/bin/env bash
# Consistency check. Run from the workspace root before building. Exits non-zero on any failure.
# Needs kdd, a running cluster context for the realm (run ./k3d.sh up first), and the realm from kdd.yaml.
set -uo pipefail

REALM="${1:-${REALM:-dev_k3d}}"   # usage: ./check.sh [realm]
CRATE="$(sed -n 's/^ *- from_file: *//p' kdd.yaml | head -n1)"   # version source, from kdd.yaml
BASE="$(sed -n 's/^block_base_dir: *//p' kdd.yaml | head -n1)"
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }

SYSTEM="$(sed -n 's/^system: *//p' kdd.yaml | head -n1)"
VERSION="$(sed -n 's/^version *= *"\([^"]*\)".*/\1/p' "$CRATE" | head -n1)"

[ -n "$SYSTEM" ] || bad "system missing in kdd.yaml"
[ -f "$CRATE" ] || bad "version source from_file not found: $CRATE"
grep -nE '^[a-z_-]+::' Cargo.toml $(dirname "$CRATE")/../*/Cargo.toml 2>/dev/null && bad "Cargo.toml has a std/module path as dependency"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || bad "version in $CRATE must be a literal X.Y.Z (got '$VERSION')"
grep -q 'workspace *= *true' <(grep '^version' "$CRATE") && bad "$CRATE uses version.workspace"

# kdd skips a listed overlay file that does not exist, silently: the realm just vanishes.
# The git-ignored kdd.local.yaml may be absent; any other listed overlay must exist.
if python3 -c 'import yaml' 2>/dev/null; then
	while IFS= read -r ov; do
		[ -f "$ov" ] || [ "$ov" = kdd.local.yaml ] || bad "overlay $ov listed in kdd.yaml does not exist (kdd skips it silently)"
	done < <(python3 - <<'PY'
import re, yaml
head = re.split(r"(?m)^---.*$", open("kdd.yaml").read())[0]
ov = (yaml.safe_load(head) or {}).get("overlays") or []
for o in ([ov] if isinstance(ov, str) else ov):
    print(o)
PY
)
fi

# realm rules (environments.md "Adding a realm"): contexts unique; every realm with confirm_delete: true
# keeps only file names of the dev set, has no secret values or Secret objects, and uses digests for own images.
if python3 -c 'import yaml' 2>/dev/null; then
	python3 - <<'PY' || fail=1
import os, re, sys, yaml

def head(p):
    return yaml.safe_load(re.split(r"(?m)^---.*$", open(p).read())[0]) or {}

bad = 0
def b(m):
    global bad
    bad = 1
    print("FAIL: " + m, file=sys.stderr)

main = {}
for doc in yaml.safe_load_all(open("kdd.yaml")):   # overlays sit in the first document, realms in a later one
    main.update(doc or {})
realms = dict(main.get("realms") or {})
ov = main.get("overlays") or []
for o in ([ov] if isinstance(ov, str) else ov):
    if os.path.isfile(o):
        realms.update(head(o).get("realms") or {})
realms.pop("_base_", None)

def files(d):
    return sorted(f for f in os.listdir(d) if not f.startswith(".")) if d and os.path.isdir(d) else None

seen = {}
for n, r in realms.items():
    c = r.get("context")
    if c in seen:
        b("realms %s and %s share context %s" % (seen[c], n, c))
    seen[c] = n

dev = set()
for n, r in realms.items():
    if not r.get("confirm_delete"):
        if files(r.get("yaml_dir")) is None:
            b("realm %s: yaml_dir %s not found (rendered output would be empty)" % (n, r.get("yaml_dir")))
        dev |= set(files(r.get("yaml_dir")) or [])
system = main.get("system")
for n, r in realms.items():
    if not r.get("confirm_delete"):
        continue
    d = r.get("yaml_dir")
    fs = files(d)
    if fs is None:
        b("realm %s: yaml_dir %s not found" % (n, d))
        continue
    for f in fs:
        if dev and f not in dev:
            b("realm %s: %s%s is not a dev-set file name (kept files keep name and number)" % (n, d, f))
        t = open(os.path.join(d, f)).read()
        if "REPLACE_ME" in t:
            b("realm %s: %s%s has REPLACE_ME (secrets come from the store)" % (n, d, f))
        if re.search(r"(?m)^kind: Secret\s*$", t):
            b("realm %s: %s%s defines a Secret object" % (n, d, f))
        for m in re.finditer(r'(?m)^\s*image:\s*"?([^"\s]+)', t):
            if re.search(r"/(%s|{{system}})-" % re.escape(str(system)), m.group(1)) and "@" not in m.group(1):
                b("realm %s: %s%s image %s must be a digest reference" % (n, d, f, m.group(1)))
sys.exit(bad)
PY
fi

# k3d.sh constants must agree with the kdd.yaml realm (cluster, registry host and port)
if [ -f k3d.sh ]; then
	K_CLUSTER="$(sed -n 's/^CLUSTER=//p' k3d.sh | head -n1)"
	K_REG="$(sed -n 's/^REG_NAME=//p' k3d.sh | head -n1)"
	K_PORT="$(sed -n 's/^REG_PORT=//p' k3d.sh | head -n1)"
	[ -n "$K_CLUSTER" ] && [ -n "$K_REG" ] && [ -n "$K_PORT" ] || bad "k3d.sh must define CLUSTER, REG_NAME and REG_PORT"
	[ "$K_REG" = "${K_CLUSTER}-reg.localhost" ] || bad "k3d.sh REG_NAME ($K_REG) must be CLUSTER-reg.localhost (${K_CLUSTER}-reg.localhost)"
	grep -qE "registry: *k3d-${K_REG}:${K_PORT}( |$|,|\})" kdd.yaml || bad "kdd.yaml registry must be k3d-${K_REG}:${K_PORT} (k3d.sh)"
	grep -qE "context: *k3d-${K_CLUSTER}( |$|,|\})" kdd.yaml || bad "kdd.yaml context must be k3d-${K_CLUSTER} (k3d.sh)"
fi

# kdd selects a realm by kubectl context and asks to create a missing one: never let it prompt.
kubectl config current-context >/dev/null 2>&1 || { echo "FAIL: no kubectl context. Create the cluster first (./k3d.sh up)." >&2; exit 1; }
timeout 60 kdd realm "$REALM" </dev/null || { echo "FAIL: kdd realm $REALM (does its context exist?)" >&2; exit 1; }
timeout 60 kdd ktemplate </dev/null || { echo "FAIL: kdd ktemplate" >&2; exit 1; }
OUT="$(ls -d k8s/*/.out/"$REALM" 2>/dev/null | head -n1)"
[ -d "$OUT" ] || { bad "no rendered output for realm $REALM"; exit 1; }

# hardening rules (lint.py, same directory as this script)
if python3 -c 'import yaml' 2>/dev/null; then
	python3 ./lint.py "$OUT" || fail=1
else
	bad "PyYAML missing: pacman -S python-yaml (Debian: apt install python3-yaml)"
fi

grep -rn '{{\|&#x3D;\|{ workspace' "$OUT" && bad "unresolved template or workspace value in rendered output"
# images this system builds must carry the system version; third-party images are pinned by lint.py (ctr-image-tag)
grep -rhn 'image:' "$OUT" | grep "[/\"]${SYSTEM}-" | grep -v -e ":$VERSION\"" -e '@sha256:' && bad "own image tag != $VERSION (or not a digest)"
grep -rhn 'image:.*latest' "$OUT" && bad "latest tag"

for f in "$OUT"/*.yaml; do
	for b in $(sed -n "s/.*${SYSTEM}-\([a-z0-9-]*\):${VERSION}.*/\1/p" "$f" | sort -u); do
		[ -f "${BASE}$b/Dockerfile" ] || bad "image block '$b' has no ${BASE}$b/Dockerfile"
	done
done
grep -rhn 'run:' "$OUT" | grep -v "\"\?${SYSTEM}-" && bad "run label not prefixed with system '$SYSTEM'"

# every env var read in code must be set for a workload in the rendered output: a ConfigMap/Secret key or an env name.
# Blocks that are not deployed in this realm are skipped. Keys of a Secret that is referenced but not defined
# (it comes from the secret store, environments.md) cannot be seen here and are not reported.
SYSTEM="$SYSTEM" BASE="$BASE" OUT="$OUT" python3 - <<'PY' || fail=1
import glob, os, re, sys, yaml
system, base, out = os.environ["SYSTEM"], os.environ["BASE"], os.environ["OUT"]
docs = []
for f in glob.glob(os.path.join(out, "*.yaml")):
    docs += [d for d in yaml.safe_load_all(open(f)) if isinstance(d, dict)]
text = "\n".join(open(f).read() for f in glob.glob(os.path.join(out, "*.yaml")))
present = set(re.findall(r"[/\"]%s-([a-z0-9-]+)[:@]" % re.escape(system), text))
absent = [os.path.join(base, d) + os.sep for d in os.listdir(base) if os.path.isfile(os.path.join(base, d, "Dockerfile")) and d not in present] if os.path.isdir(base) else []
names, defined, refs = set(), set(), set()
def pods(d):
    spec = d.get("spec") or {}
    t = (spec.get("template") or {}).get("spec") or (((spec.get("jobTemplate") or {}).get("spec") or {}).get("template") or {}).get("spec") or {}
    return t.get("containers", []) + t.get("initContainers", [])
for d in docs:
    k, md = d.get("kind"), d.get("metadata") or {}
    if k in ("ConfigMap", "Secret"):
        names |= set((d.get("data") or {}).keys()) | set((d.get("stringData") or {}).keys())
        if k == "Secret": defined.add(md.get("name"))
    for c in pods(d):
        names |= {e.get("name") for e in c.get("env", [])}
        for e in c.get("env", []):
            r = (e.get("valueFrom") or {}).get("secretKeyRef")
            if r: refs.add(r.get("name"))
        for e in c.get("envFrom", []):
            if "secretRef" in e: refs.add(e["secretRef"].get("name"))
external = bool(refs - defined)
used = set()
for f in glob.glob("crates/**/*.rs", recursive=True):
    if any(f.startswith(a) for a in absent): continue
    used |= set(re.findall(r'env::var\("([A-Z_0-9]+)"\)', open(f).read()))
bad = 0
for v in sorted(used - names):
    if external: continue
    print("FAIL: env var %s used in code but not set in manifests" % v, file=sys.stderr); bad = 1
sys.exit(bad)
PY

# scripts must not mask failures
[ -f k3d.sh ] && grep -n '|| true' k3d.sh && bad "k3d.sh masks failures with '|| true' (create only if absent instead)"

# Dockerfiles: locked build, numeric non-root user, exec-form entrypoint, no :latest
for df in ${BASE}*/Dockerfile; do
	[ -f "$df" ] || continue
	grep -q 'cargo build --locked' "$df" || bad "$df: cargo build must use --locked"
	grep -qE '^USER [0-9]+' "$df" || bad "$df: needs a numeric USER"
	grep -qE '^ENTRYPOINT \[' "$df" || bad "$df: ENTRYPOINT must be exec form"
	grep -E '^FROM ' "$df" | grep -E ':latest( |$)' && bad "$df: FROM uses :latest"
done

[ $fail -eq 0 ] && echo "OK: system=$SYSTEM version=$VERSION"
exit $fail
