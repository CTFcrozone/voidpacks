# CI

`samples/ci/github-actions.yml` is the reference pipeline. It runs the same gates a developer runs locally, so CI and local cannot drift. Adapt the syntax for another CI system; keep the gates.

## Gates

| Job | Checks | Why |
|---|---|---|
| `rust` | `cargo fmt --check`, `clippy -D warnings`, `cargo test --locked`, `cargo-deny` | Code quality, licenses, known advisories, banned crates. |
| `manifests` | `./check.sh <realm>` (names, versions, labels, env vars, registry/cluster agreement, `lint.py` hardening), `kubeconform -strict` | Contract and hardening enforced before any image is built. Schema errors found without a cluster. |
| `images` | build once per service, Trivy scan (fail on HIGH/CRITICAL), SBOM, keyless cosign signature by digest | Supply chain: what runs is what was built, scanned and signed. |
| `release` | collects image digests into `release.json` | The production render references images by digest (`environments.md`). |

## Rendering without a cluster

kdd selects a realm by kubectl context but renders from files. In CI, create an empty context with the realm's context name (`kubectl config set-cluster` / `set-context`) so `kdd realm` and `kdd ktemplate` work with no cluster. `check.sh` needs only that context. Confirm this with your kdd build before relying on it.

## Rules

- **Pin actions by commit SHA** and review updates. Tags in the sample are for readability.
- **No long-lived credentials.** Use OIDC to the registry and keyless signing. No registry passwords in repository secrets.
- **Build on every PR, push only from `main`.** PR builds validate Dockerfiles without publishing.
- **One build per commit.** Staging and production consume the same digest.
- **CI does not apply to production.** Use a protected environment with required reviewers, or a human running `kdd kapply` (`environments.md`).
- **Branch protection:** require `rust`, `manifests` and `images` before merge; require review; block force pushes.
- **Caches and artifacts** hold no secrets. Keep rendered manifests per release as artifacts for rollback.

## Local equivalent

```sh
cargo fmt --all --check && cargo clippy --workspace --all-targets --locked -- -D warnings && cargo test --workspace --locked
./k3d.sh up && ./check.sh
```

## Not covered

Dependency update automation, runtime image scanning, admission policy (Kyverno/Gatekeeper) and signature verification at admission. Add them when a team needs enforcement in the cluster, not only in the pipeline.
