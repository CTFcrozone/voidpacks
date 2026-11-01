# Parameters and defaults

Rules in this pack are generic. Concrete names and versions in guides and samples (`rust10x`, `192.168.0.104`, `cloudapp`, a Rust or Postgres tag) are examples. Never copy them into a user's project.

## Precedence

When two sources disagree: user parameters, then the reference projects (`samples/minimal/`, `samples/web-db/`, `samples/web-app/`), then guide text, then snippets in guides. Reference projects are verified; snippets are illustrations. If a reference and a snippet differ, follow the reference.

## Resolution order

1. Value stated by the user (prompt parameters, request).
2. Value already in the project: `rust-toolchain.toml`, `Cargo.toml`, `kdd.yaml`, existing manifests.
3. Policy default below. State which default was used in the answer.

Do not write "current" versions from memory. If a value must be the latest and cannot be verified, use the floating form below or say "assumed X, verify".

## Policy

| Parameter | Policy |
|---|---|
| system, namespace, cluster, registry, hostnames | From the user or project. If absent, derive from the directory name and say so. One definition each (see `contract.md`). |
| Rust toolchain | `rust-toolchain.toml` if present (match it exactly). Else user pin. Else latest stable: floating `rust:1-<variant>` through an `ARG` (see `containers.md`). Pin an exact tag, and a digest in production realms, only when asked or for prod. |
| `rust-version` (MSRV) / edition | Set `rust-version` only if the user wants an MSRV. Never invent one. Builder must be at least any dependency's requirement. Edition: latest stable edition of the chosen toolchain. |
| Crate dependencies | Real crates.io crates only, latest compatible via `cargo add` semantics, locked by `Cargo.lock`. Never `std`, `core` or `alloc` paths as dependencies. Build with `--locked`. |
| Runtime base OS | Current stable release of the chosen family (`alpine:3` floating, or Debian stable). Never an EOL release; check the vendor's EOL date. |
| Stateful engines (PostgreSQL, Valkey) | Pin an explicit major version. Default: latest stable major at creation time. Never a floating major: a data directory is not forward-compatible, so an unpinned tag breaks on pod restart. Upgrades are procedures (`database.md`). |
| Kubernetes API versions | GA versions the target cluster serves (`kubectl api-resources`). No beta without a reason. |
| Ports, UIDs, resources | Choose once, document in a table at the top of the manifest, reference everywhere. Dev sizes are small; production sizes come from measurements. |
| Image tag | From the single version source. Never `latest`. |

## Prompt parameter block

A project prompt should open with a block like this and refer to it, instead of repeating values:

```
SYSTEM=<name>  NAMESPACE=<ns>  CLUSTER=<name>  REGISTRY_PORT=5000  REALM=<realm>
RUST=latest | <pin>    BASE_OS=alpine | debian    PG_MAJOR=<n>
```
