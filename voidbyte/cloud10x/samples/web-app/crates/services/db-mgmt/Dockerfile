# syntax=docker/dockerfile:1
# Build context: workspace root.
#   docker build -f crates/services/db-mgmt/Dockerfile -t <registry>/rust10x-db-mgmt:<version> .
FROM rust:1.94-slim-bookworm AS builder
WORKDIR /build
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/build/target \
    cargo build --locked --release -p db-mgmt \
 && cp target/release/db-mgmt /db-mgmt

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libssl3 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /service
COPY --from=builder /db-mgmt ./db-mgmt
COPY crates/services/db-mgmt/sql ./sql
USER 10001
ENTRYPOINT ["/service/db-mgmt"]
