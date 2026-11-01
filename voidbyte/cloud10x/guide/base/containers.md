# Containers

## Dockerfile rules

- Multi-stage: build stage compiles, runtime stage only runs.
- Base images: follow `parameters.md`. Language toolchain images float to the latest stable by default (`ARG`, below). Stateful images (Postgres, Valkey) are pinned to an explicit major. Production realms pin every image by digest.
- Runtime OS: a currently supported release only (Alpine `3`, or Debian stable). Never an EOL release; check the vendor's date. Note: on newer Debian the OpenSSL runtime package may be `libssl3t64`. Prefer rustls and avoid the question.
- Runtime stage installs runtime libraries only (`ca-certificates`, `libssl3`), never `-dev` packages. Prefer rustls to avoid OpenSSL entirely.
- Run as a non-root numeric user: `USER 10001`. Match `runAsUser` in the manifest.
- `ENTRYPOINT` in exec form, directly on the binary. No `bash -c`, no `source ~/.bashrc`, no `tail -f /dev/null`.
- Build with `--locked` so `Cargo.lock` is honored.
- Builder image: `ARG RUST_TAG=1-<variant>` then `FROM rust:${RUST_TAG}`. `1-<variant>` always resolves to the latest stable Rust 1.x, so no version is written from memory. To pin, build with `--build-arg RUST_TAG=<exact>-<variant>` or edit the default; if `rust-toolchain.toml` exists, set it to that version. Variants: `alpine` (musl), `slim` (Debian). Symptom of a toolchain older than a dependency needs: `error: rustc X is not supported by the following packages`; fix by raising the toolchain, never by downgrading crates.
- Add a `.dockerignore` (`target/`, `.git/`, `rs-builder/rs-builder-target/`, local env files).
- Cache dependencies: BuildKit cache mounts or `cargo-chef`. Avoid cache-busting `COPY . .` before dependency resolution when build time matters.

Rust workspace service (build context = workspace root). This is the canonical Dockerfile; it is `samples/minimal/crates/services/web-server/Dockerfile` verbatim. Do not use any other layout (no `WORKDIR /service`, no shell entrypoint):

```dockerfile
# syntax=docker/dockerfile:1
# Build context: workspace root.
# Floats to the latest stable Rust 1.x. Pin: --build-arg RUST_TAG=<version>-alpine
ARG RUST_TAG=1-alpine
FROM rust:${RUST_TAG} AS builder
RUN apk add --no-cache musl-dev
WORKDIR /build
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/build/target \
    cargo build --locked --release -p web-server \
 && cp target/release/web-server /web-server

FROM alpine:3
RUN apk add --no-cache ca-certificates
COPY --from=builder /web-server /web-server
USER 10001:10001
ENTRYPOINT ["/web-server"]
```

Variants: replace the crate name for other binaries. For a Debian runtime use `rust:${RUST_TAG}` with `RUST_TAG=1-slim`, drop the `apk` lines, and install `ca-certificates` with `apt-get` in the runtime stage. Static assets, if any, are copied explicitly to a fixed path and referenced by absolute path from the binary.

Build outside kdd (the workspace root is the context; `kdd dbuild` uses the block folder), tag with kdd's local prefix, then let kdd push:

```sh
docker build -f crates/services/web-server/Dockerfile -t localhost:5000/rust10x-web-server:<version> .
kdd dpush web-server
```

## Entrypoint and PID 1

- The service binary is PID 1 and receives `SIGTERM` directly. It must shut down gracefully on it.
- A wrapper script that backgrounds the binary and idles (`tail -f /dev/null`) hides crashes from Kubernetes and swallows signals. Do not use it.
- If a wrapper is unavoidable, it must `exec` the binary, or `trap` signals and `wait` on the child PID.

## Infrastructure images

```dockerfile
# db
FROM postgres:18
```

```dockerfile
# queue
FROM valkey/valkey:8.1.3-bookworm
EXPOSE 6379
```

- Keep the image thin; configure through env vars and mounted config.
- Official `postgres:18` expects its volume mounted at `/var/lib/postgresql` (not `/var/lib/postgresql/data`).

## Tagging

- `{registry}/{system}-{block}:{image_tag}` (see `kdd.md`). Tag = application version.
- Never `latest`. Production tags are immutable; enforce in the registry.
- Enterprise: scan images before release, generate an SBOM, sign images (cosign) and verify at admission.

## Dev fast loop (minikube only)

Compile once in a builder container, mount the binary into a stock image, skip rebuilds per change.

```sh
docker build -t rs-builder -f ./rs-builder/Dockerfile .
./builder-rs.sh                          # binaries land in rs-builder/rs-builder-target/
minikube mount "$(pwd)":/mnt             # keep running
```

The manifest mounts `/mnt/rs-builder/rs-builder-target/<bin>` through `hostPath`. This is dev-only: `hostPath` violates Pod Security `baseline` and must never reach a shared cluster. Real realms deploy built images.
