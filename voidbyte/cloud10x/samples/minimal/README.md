# Minimal reference project

The smallest complete cloud10x project: one hardened Rust service, deployed to k3d with kdd. It compiles, runs and passes `check.sh` / `lint.py` as shipped. Copy `check.sh` and `lint.py` from `../web-app/` into a project built from it.

Names here are examples (`rust10x`, `rust10x-web-app`, `cloudapp`, `api.rust10x.local`, port `5000`, realm `dev_k3d`, toolchain `1-alpine`). A real project replaces them everywhere, consistently, and changes nothing else.

Files: `Cargo.toml`, `crates/services/web-server/{Cargo.toml,Dockerfile,src/main.rs}`, `kdd.yaml`, `k3d.sh`, `k8s/dev_k3d/00-namespace` ... `03-network-policy`, `.gitignore`, `.dockerignore`.
