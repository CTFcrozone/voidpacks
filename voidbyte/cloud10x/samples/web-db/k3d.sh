#!/usr/bin/env bash
# Local k3d cluster, image build/push and staged deploy with kdd. Run from the project root.
#   ./k3d.sh up       create registry + cluster (idempotent), select the kdd realm
#   ./k3d.sh build    build the image, push with kdd
#   ./k3d.sh deploy   apply manifests in stages, gated by kubectl
#   ./k3d.sh all      build + deploy
# Requires: docker, k3d, kubectl, kdd. /etc/hosts needs:
#   127.0.0.1 k3d-cloudapp-reg.localhost api.rust10x.local
# kdd exits 0 even on failure, so every stage is gated by kubectl.
set -euo pipefail

SYSTEM="$(sed -n 's/^system: *//p' kdd.yaml | head -n1)"   # single source: kdd.yaml
CLUSTER=cloudapp
REG_NAME=cloudapp-reg.localhost
REG_PORT=5000
REALM=dev_k3d
NS=rust10x-web-app

VERSION="$(sed -n 's/^version *= *"\([^"]*\)".*/\1/p' crates/services/web-server/Cargo.toml | head -n1)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "bad version '$VERSION' (literal X.Y.Z needed in web-server Cargo.toml)" >&2; exit 1; }
[ -n "$SYSTEM" ] || { echo "system missing in kdd.yaml" >&2; exit 1; }

up() {
	k3d registry list | grep -qE "^k3d-${REG_NAME}[[:space:]]" \
		|| k3d registry create "$REG_NAME" --port "$REG_PORT"
	k3d cluster list | grep -qE "^${CLUSTER}[[:space:]]" \
		|| k3d cluster create "$CLUSTER" \
			-p "80:80@loadbalancer" -p "443:443@loadbalancer" \
			--registry-use "k3d-${REG_NAME}:${REG_PORT}"
	kdd realm "$REALM"
	# klog / kexec run kubectl in the context's current namespace.
	kubectl config set-context --current --namespace="$NS"
}

build() {
	# kdd's docker build uses the block folder as context; these need the workspace root,
	# so build here, tag with kdd's local prefix, and let kdd push (retags to the realm registry).
	for svc in web-server db-mgmt; do
		docker build -f "crates/services/$svc/Dockerfile" \
			-t "localhost:5000/${SYSTEM}-${svc}:${VERSION}" .
	done
	kdd realm "$REALM"
	kdd dpush web-server,db-mgmt
}

deploy() {
	kdd realm "$REALM"
	kdd kapply 00-namespace,01-config,02-secrets,03-postgres
	kubectl -n "$NS" rollout status "statefulset/${SYSTEM}-db" --timeout=180s

	# Job specs are immutable: recreate on every deploy.
	kubectl -n "$NS" delete job "${SYSTEM}-db-mgmt" --ignore-not-found
	kdd kapply 04-db-mgmt-job
	kubectl -n "$NS" wait --for=condition=complete "job/${SYSTEM}-db-mgmt" --timeout=300s

	kdd kapply 05-web-server,06-ingress,07-network-policy
	kubectl -n "$NS" rollout status "deployment/${SYSTEM}-web-server" --timeout=180s
}

case "${1:-}" in
	up) up ;;
	build) build ;;
	deploy) deploy ;;
	all) build; deploy ;;
	*) echo "usage: $0 {up|build|deploy|all}" >&2; exit 2 ;;
esac
