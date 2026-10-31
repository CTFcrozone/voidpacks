#!/usr/bin/env bash
# Build, push and deploy to a local k3d cluster with kdd. Run from the workspace root.
#   ./k3d.sh up       create registry + cluster, select realm (once)
#   ./k3d.sh build    build images, push with kdd
#   ./k3d.sh deploy   apply manifests in stages
#   ./k3d.sh all      build + deploy
#
# Requires: docker, k3d, kubectl, kdd (realm `dev_k3d` in kdd.yaml).
# Docker on the host must resolve k3d-rust10x-reg.localhost
# (add `127.0.0.1 k3d-rust10x-reg.localhost` to /etc/hosts if it does not).
#
# kdd exits 0 even on failure, so every stage is gated by kubectl.
set -euo pipefail

SYSTEM=rust10x
CLUSTER=rust10x
REG_NAME=rust10x-reg.localhost
REG_PORT=5000
REALM=dev_k3d
NS=rust10x-web-app

VERSION="$(sed -n 's/^version *= *"\(.*\)"/\1/p' crates/services/web-server/Cargo.toml | head -n1)"

up() {
	k3d registry create "$REG_NAME" --port "$REG_PORT"
	k3d cluster create "$CLUSTER" \
		-p "80:80@loadbalancer" -p "443:443@loadbalancer" \
		--registry-use "k3d-${REG_NAME}:${REG_PORT}"
	kdd realm "$REALM"
	# klog / kexec run kubectl in the context's current namespace.
	kubectl config set-context --current --namespace="$NS"
}

build() {
	# Workspace services need the workspace root as build context, so docker build runs
	# outside kdd. Tag with kdd's local prefix; `kdd dpush` retags to the realm registry.
	for svc in web-server db-mgmt; do
		docker build -f "crates/services/$svc/Dockerfile" \
			-t "localhost:5000/${SYSTEM}-${svc}:${VERSION}" .
	done
	kdd realm "$REALM"
	kdd dpush web-server,db-mgmt
}

deploy() {
	kdd realm "$REALM"
	kdd kapply 00-namespace,01-config,02-secrets,03-postgres,04-valkey
	kubectl -n "$NS" rollout status statefulset/rust10x-db --timeout=180s

	# Job specs are immutable: recreate on every deploy.
	kubectl -n "$NS" delete job rust10x-db-mgmt --ignore-not-found
	kdd kapply 05-db-mgmt-job
	kubectl -n "$NS" wait --for=condition=complete job/rust10x-db-mgmt --timeout=300s

	kdd kapply 06-web-server,07-ingress,08-network-policy
	kubectl -n "$NS" rollout status deployment/rust10x-web-server --timeout=180s
}

case "${1:-}" in
	up) up ;;
	build) build ;;
	deploy) deploy ;;
	all) build; deploy ;;
	*) echo "usage: $0 {up|build|deploy|all}" >&2; exit 2 ;;
esac
