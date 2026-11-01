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
