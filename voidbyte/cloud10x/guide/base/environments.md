# Environments and promotion

One codebase, several realms. A realm differs from another in destination values (cluster, registry, hostnames, sizes, secret source), never in structure.

## Principles

- **Build once, promote the artifact.** The image tested in staging is the image applied to production. No rebuild per environment.
- **Immutable references.** Production references images by digest (`@sha256:...`); lower realms may use the version tag. Never `latest`. Enable tag immutability on the registry.
- **Same manifests, different values.** Everything that varies (replicas, resources, hostnames, DB host) is a realm variable. Do not fork manifests per environment.
- **Secrets come from a store.** `REPLACE_ME` placeholders exist only for local realms. Non-local realms read secrets from a secret manager or an operator; no hand-applied values.
- **A human or an approved pipeline applies to production.** Agents author files; they do not run `kdd kapply` against staging or production.
- **Production is the source of truth for data.** Never copy production data to lower realms unanonymized (`database.md`).

## Ladder

| Realm | Purpose | Cluster | Database | Secrets | Images | `confirm_delete` | Applied by |
|---|---|---|---|---|---|---|---|
| local (`dev_k3d`) | inner loop | k3d / minikube | in-cluster StatefulSet | `REPLACE_ME` | version tag, local registry | false | developer |
| `dev` | shared integration | shared dev cluster | in-cluster or small managed | secret store | version tag | false | developer / CI |
| `staging` | prod rehearsal | prod-like, same Kubernetes minor and ingress | same engine and major as prod | secret store | digest | true | CI with approval |
| `prod` | customers | dedicated, hardened | managed (RDS, Cloud SQL) or operator | secret store | digest | true | approved pipeline or human |

Staging must be prod-like in everything the failing deploy would touch: same ingress class, same NetworkPolicy engine, same Pod Security labels, same Postgres major.

## Realm design in kdd

- Name realms `<env>` or `<env>_<cluster>`. The `context` is unique per realm; kdd selects the current realm by context (`kdd.md`).
- Put shared defaults in `realms._base_` and per-realm values in the realm. Realm keys are available as `{{var}}` in manifests.
- Layout: one committed overlay per environment (`staging/kdd-staging.yaml`, `prod/kdd-prod.yaml`), listed in `overlays:` in `kdd.yaml` (`kdd.md`). Overlay realms replace same-name realms and inherit `_base_`. Paths inside them (`yaml_dir`) stay relative to the kdd root.
- Keep account IDs, ARNs and registry hostnames out of committed files in public repos: put those realms in the git-ignored overlay `kdd.local.yaml` instead.
- `profile` (AWS CLI profile) and `project` (GCP) belong to the realm. The provider follows the context name prefix (`arn:aws` -> AWS with ECR repo creation and login retry, `gke` -> GCP).

Placeholder example (see `samples/web-app/kdd.overlay.example.yaml`):

```yaml
realms:
  _base_:
    replicas: 1
    web_cpu_limit: 500m
  staging:
    yaml_dir: k8s/staging/
    context: <staging-context>
    registry: <registry-host>          # no trailing slash
    confirm_delete: true
    replicas: 2
  prod:
    yaml_dir: k8s/prod/
    context: <prod-context>
    registry: <registry-host>
    profile: <cloud-cli-profile>
    confirm_delete: true
    replicas: 3
    web_cpu_limit: "1"
```

Manifests use `replicas: {{replicas}}` and the limits from variables. `yaml_dir` for staging and production is the dev set with only the differences applied (files removed, for example the in-cluster database when `MANAGED_DB`, and variables substituted).

## Image references by digest

kdd pushes tags (`kdd dpush`). Resolve the digest after the push and give it to the render step as data:

```sh
docker inspect --format '{{index .RepoDigests 0}}' <registry>/<system>-web-server:<version>   # <repo>@sha256:...; keep the part after @
```

CI writes the digests to a small `release.json` (for example `{"web_server_digest": "sha256:..."}`), kdd reads it through a `vars` `from_file` entry (JSON is supported), and the production manifest uses:

```yaml
image: "{{registry}}/{{system}}-web-server@{{web_server_digest}}"
```

`lint.py` accepts digest references. Verify how your kdd build behaves when `release.json` is absent (local realms): provide an empty default file or keep digest handling in the production pipeline's overlay.

## Promotion flow

1. Merge to main. CI runs format, lint, tests, dependency audit, `check.sh`, manifest validation.
2. CI builds images once, scans, signs, pushes the version tag and records digests in `release.json`.
3. Staging: CI applies after approval. Database changes ship as a drop (`database.md`), rehearsed on a restored copy.
4. Smoke tests on staging (`/health`, `/ready`, one business flow).
5. Production: render with `kdd ktemplate`, diff against the previous release's rendered output, review, then an approved pipeline or a human runs `kdd kapply` in staged groups (config, database, workloads) with readiness gates (`kdd` does not wait for readiness; gate with `kubectl rollout status`).
6. Keep the rendered `.out/<realm>/` of each release as a pipeline artifact. It is the rollback input.

## Pre-apply checklist (production)

- [ ] `./check.sh <realm>` passes on the exact commit.
- [ ] Images scanned and signed; digests recorded.
- [ ] Rendered diff reviewed; no unexpected resource deleted (`confirm_delete: true` stays on).
- [ ] Database drop reviewed and rehearsed; a verified backup exists.
- [ ] Rollback prepared: previous release's rendered manifests and previous digests available.
- [ ] No `REPLACE_ME`, no `latest`, no committed key material.
- [ ] Approver is not the author.

## Rollback

- Application: re-apply the previous release's rendered manifests (previous digests). Deployments roll back with no data change.
- Database: schema changes are not rolled back by redeploying. Restore from the pre-drop backup or ship a corrective drop (`database.md`).
- Decide which applies before the release, not during the incident.
