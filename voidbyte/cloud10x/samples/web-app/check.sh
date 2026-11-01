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
VERSION="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$CRATE" | head -n1)"

[ -n "$SYSTEM" ] || bad "system missing in kdd.yaml"
[ -f "$CRATE" ] || bad "version source from_file not found: $CRATE"
grep -nE '^[a-z_-]+::' Cargo.toml $(dirname "$CRATE")/../*/Cargo.toml 2>/dev/null && bad "Cargo.toml has a std/module path as dependency"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || bad "version in $CRATE must be a literal X.Y.Z (got '$VERSION')"
grep -q 'workspace *= *true' <(grep '^version' "$CRATE") && bad "$CRATE uses version.workspace"

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
grep -rhn 'image:' "$OUT" | grep "[/\"]${SYSTEM}-" | grep -v ":$VERSION\"" && bad "own image tag != $VERSION"
grep -rhn 'image:.*latest' "$OUT" && bad "latest tag"

for f in "$OUT"/*.yaml; do
	for b in $(sed -n "s/.*${SYSTEM}-\([a-z0-9-]*\):${VERSION}.*/\1/p" "$f" | sort -u); do
		[ -f "${BASE}$b/Dockerfile" ] || bad "image block '$b' has no ${BASE}$b/Dockerfile"
	done
done
grep -rhn 'run:' "$OUT" | grep -v "\"\?${SYSTEM}-" && bad "run label not prefixed with system '$SYSTEM'"

# every env var read in code must exist in the manifests
for v in $(grep -rhoE 'env::var\("[A-Z_]+"\)|std::env::var\("[A-Z_]+"\)' crates | sed 's/.*("\(.*\)")/\1/' | sort -u); do
	grep -rq "$v" "$OUT" || bad "env var $v used in code but not set in manifests"
done

[ $fail -eq 0 ] && echo "OK: system=$SYSTEM version=$VERSION"
exit $fail
