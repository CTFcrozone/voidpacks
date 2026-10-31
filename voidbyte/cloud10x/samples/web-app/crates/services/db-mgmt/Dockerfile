# syntax=docker/dockerfile:1
# Build context: workspace root.
#   docker build -f crates/services/db-mgmt/Dockerfile -t <registry>/rust10x-db-mgmt:<version> .
# Floats to latest stable Rust 1.x. Pin: --build-arg RUST_TAG=<ver>-slim
ARG RUST_TAG=1-slim
FROM rust:${RUST_TAG} AS builder
WORKDIR /build
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/build/target \
    cargo build --locked --release -p db-mgmt \
 && cp target/release/db-mgmt /db-mgmt

FROM debian:stable-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libssl3 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /service
COPY --from=builder /db-mgmt ./db-mgmt
COPY crates/services/db-mgmt/sql ./sql
USER 10001
ENTRYPOINT ["/service/db-mgmt"]
