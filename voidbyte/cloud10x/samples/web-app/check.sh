#!/usr/bin/env bash
# Consistency check. Run from the workspace root before building. Exits non-zero on any failure.
# Needs kdd and the realm from kdd.yaml (REALM below).
set -uo pipefail

REALM=dev_k3d
CRATE=crates/services/web-server/Cargo.toml
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }

SYSTEM="$(sed -n 's/^system: *//p' kdd.yaml | head -n1)"
VERSION="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$CRATE" | head -n1)"

[ -n "$SYSTEM" ] || bad "system missing in kdd.yaml"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || bad "version in $CRATE must be a literal X.Y.Z (got '$VERSION')"
grep -q 'workspace *= *true' <(grep '^version' "$CRATE") && bad "$CRATE uses version.workspace"

kdd realm "$REALM" >/dev/null && kdd ktemplate >/dev/null
OUT="$(ls -d k8s/*/.out/"$REALM" 2>/dev/null | head -n1)"
[ -d "$OUT" ] || { bad "no rendered output for realm $REALM"; exit 1; }

grep -rn '{{\|&#x3D;\|{ workspace' "$OUT" && bad "unresolved template or workspace value in rendered output"
grep -rhn 'image:' "$OUT" | grep -v "postgres:" | grep -v ":$VERSION\"" && bad "image tag != $VERSION"
grep -rhn 'image:.*latest' "$OUT" && bad "latest tag"

for f in "$OUT"/*.yaml; do
	for b in $(sed -n "s/.*${SYSTEM}-\([a-z0-9-]*\):${VERSION}.*/\1/p" "$f" | sort -u); do
		[ -f "crates/services/$b/Dockerfile" ] || bad "image block '$b' has no crates/services/$b/Dockerfile"
	done
done
grep -rhn 'run:' "$OUT" | grep -v "\"\?${SYSTEM}-" && bad "run label not prefixed with system '$SYSTEM'"

# every env var read in code must exist in the manifests
for v in $(grep -rhoE 'env::var\("[A-Z_]+"\)|std::env::var\("[A-Z_]+"\)' crates | sed 's/.*("\(.*\)")/\1/' | sort -u); do
	grep -rq "$v" "$OUT" || bad "env var $v used in code but not set in manifests"
done

[ $fail -eq 0 ] && echo "OK: system=$SYSTEM version=$VERSION"
exit $fail
