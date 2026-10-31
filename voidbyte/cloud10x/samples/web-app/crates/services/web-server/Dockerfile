# syntax=docker/dockerfile:1
# Build context: workspace root.
#   docker build -f crates/services/web-server/Dockerfile -t <registry>/rust10x-web-server:<version> .
FROM rust:1.94-slim-bookworm AS builder
WORKDIR /build
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/build/target \
    cargo build --locked --release -p web-server \
 && cp target/release/web-server /web-server

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libssl3 \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /service
COPY --from=builder /web-server ./web-server
COPY web-folder ./web-folder
USER 10001
ENTRYPOINT ["/service/web-server"]
