# Database

PostgreSQL. Fast iteration in development, reliability in production. The production database is the single source of truth.

## Environments

| Aspect | Development | Production |
|--------|-------------|------------|
| Runtime | PostgreSQL StatefulSet | Managed (RDS, Cloud SQL) |
| Initialization | Latest schema + anonymized data, or `sql/dev_initial` + seed | Schema snapshot + numbered drops |
| Schema changes | Replay from scratch | Drops only |
| Backups | Optional | Automated, multi-AZ, point-in-time recovery |
| Access | `kubectl port-forward` | Application only |

Applications connect through one Kubernetes Service name and one env var (`SERVICE_DB_URL`). Nothing in code distinguishes StatefulSet from managed.

## Credentials

| Secret | Keys |
|--------|------|
| `postgres-secret` | `POSTGRES_PASSWORD` (superuser password for the PostgreSQL pod) |
| `db-secret` | `SERVICE_DB_URL` (app role; web server and `db-mgmt`) |
| `db-admin-secret` | `SERVICE_PG_ROOT_URL` (admin; `db-mgmt` Job only) |

- The web server gets `SERVICE_DB_URL` only. The admin URL lives in its own Secret and is mounted solely into the `db-mgmt` Job.
- App role: least privilege (no `SUPERUSER`, no `CREATEDB`). Production backups use a dedicated read-only role.
- Dev passwords are placeholders in samples. Production secrets come from a secret manager.

## Development database (StatefulSet)

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata: { name: rust10x-db, namespace: rust10x-web-app }
spec:
  serviceName: rust10x-db
  replicas: 1
  selector: { matchLabels: { app: rust10x-db } }
  template:
    metadata: { labels: { app: rust10x-db } }
    spec:
      containers:
        - name: postgres
          image: postgres:18
          ports: [{ containerPort: 5432 }]
          volumeMounts:
            - { name: data, mountPath: /var/lib/postgresql }
  volumeClaimTemplates:
    - metadata: { name: data }
      spec:
        accessModes: [ReadWriteOnce]
        resources: { requests: { storage: 5Gi } }
```

- `postgres:18` expects its volume at `/var/lib/postgresql`.
- `volumeClaimTemplates` is mandatory; without it the pod never schedules.
- Full hardened version (probes, security context, secrets): `samples/web-app/k8s/dev_k3s/03-postgres.yaml`.

## db-mgmt service

A Rust CLI packaged as an image and run as a Kubernetes Job. It never runs inside application startup.

| Command | Action |
|---------|--------|
| `init` | Create `app_db` and `app_user` if missing, apply schema, load seed or anonymized data. Dev only. |
| `upgrade` | Apply a numbered drop to the target database. |
| `backup` | Logical backup to object storage. |
| `schema-dump` | Schema-only dump for dev initialization. |
| `anonymize` | Anonymized data dump for dev/staging. |

Today's dev implementation runs `init_dev_db` (recreate database, schema, seed) from `crates/services/db-mgmt/sql/`. The commands above are the target contract.

```sh
kubectl apply -f 05-db-mgmt-job.yaml
kubectl logs -f job/rust10x-db-mgmt -n rust10x-web-app
```

- Job spec: `backoffLimit: 3`, `activeDeadlineSeconds: 300`, `ttlSecondsAfterFinished: 86400`.
- The Job starts only after PostgreSQL reports ready.

## Drop-based upgrades

Schema and data changes only. For a PostgreSQL major version change see "Major version upgrade" below.

No replay of historical migrations in production. Changes ship as **drops**: numbered bundles applied to the live database.

```
upgrades/drop-0007/
  README.md                  rationale, rollback steps
  001-add-orders-table.sql
  002-backfill-orders.sql
```

Procedure, in order:

1. **Backup** production: `pg_dump -Fc` (custom format) to `prod-storage:/prod-db-backups/prod-backup-{YYYY-MM-DD-HH-MM}-before-drop-{NNNN}.dump`.
2. **Apply** `upgrades/drop-{NNNN}/*.sql` in alphabetical order inside one transaction. Any failure rolls everything back.
3. **Schema dump** for dev: `pg_dump --schema-only --no-owner --no-acl`, gzip, upload to `dev-storage:/dev-db-backups/{ts}-dev-schema.sql.gz`.
4. **Optional anonymized data** dump to `dev-storage:/dev-db-backups/{ts}-dev-anonymized.dump`.

Rules:

- `-Fc` output is already compressed. Do not gzip it again.
- Statements that cannot run in a transaction (`CREATE INDEX CONCURRENTLY`, `VACUUM`) go in their own drop step with explicit handling, not in the transactional batch.
- Test every drop against a restored copy of production before applying.
- Old drops leave `upgrades/` and live in git history.
- For managed databases, point-in-time recovery is the primary backup. Logical dumps are an additional, portable copy.
- `pg_dump` client major version must be at least the server's.

## Major version upgrade (in-cluster StatefulSet)

Drops (above) change the schema. A **major version** change (18 to 19) is a different procedure: PostgreSQL refuses to start a new major on a data directory initialized by the old one. Bumping the image tag on the existing volume crash-loops the pod. The data volume must be recreated and the data restored from a dump. The dump/restore path below was tested on a real server; the Kubernetes steps were not.

Placeholders: `NS` namespace, `STS` the db StatefulSet (`<system>-db`), `PVC` the claim (`data-<STS>-0`, from `volumeClaimTemplates`), `DUMP` the backup file **on the operator machine**, `FROM`/`TO` majors.

Rules:

- Stream through `kubectl exec`. Dumps go to a local file with `>`, restores read stdin with `exec -i`. No port-forward, no local client versions to match, no password on a command line, no pod `/tmp` (an `emptyDir`, lost on restart). Use `-i`, never `-it`, in scripted commands.
- The official image trusts the local socket, so `-U postgres` works inside the pod with no password.
- Apply manifests with `kdd kapply <stem>`, never `kubectl apply -f k8s/...`: the source files are templates (`{{system}}`, `{{image_tag}}`) and only the rendered `.out/` files are valid YAML.
- Roles come from db-mgmt and the secrets, not from the dump. Precondition: `\du` lists only `postgres` and `app_user`; if there are other roles, also take `pg_dumpall --globals-only` and replay it first.
- Restore keeps ownership (no `--no-owner`): db-mgmt creates `app_user` and `app_db` first, so objects land owned by `app_user`.
- This procedure has downtime. If downtime is not allowed, stop: the answer is logical replication or a managed service, and the runbook states that under "Open questions" instead of improvising.
- Deleting the PVC destroys the only copy of the data on the cluster. Do it only after the dump is verified and the rehearsal passed.

Backup (and the final dump in the cutover):

```sh
kubectl -n NS exec STS-0 -- pg_dump -U postgres -Fc app_db > DUMP
kubectl -n NS exec -i STS-0 -- pg_restore -l < DUMP | head        # readable archive; non-empty
```

Row counts before and after (same command both times, outputs must be identical):

```sh
kubectl -n NS exec -i STS-0 -- psql -U postgres -d app_db -At -f - <<'SQL'
SELECT format('SELECT %L, count(*) FROM %s', c.oid::regclass, c.oid::regclass) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'r' AND n.nspname NOT IN ('pg_catalog','information_schema') ORDER BY 1 \gexec
SQL
```

Rehearsal (required before the cutover): render `03-postgres` (`kdd ktemplate 03-postgres`), copy the rendered StatefulSet and Service to a scratch file with new names, selector labels and `serviceName` (`<STS>-rehearsal`), the same ServiceAccount, image `postgres:TO`, and its own `volumeClaimTemplates`. It must still pass the hardening rules. Apply it, wait for ready, run db-mgmt's two statements by hand or restore into it as below, `kubectl exec -i <STS>-rehearsal-0 -- pg_restore -U postgres -d app_db --exit-on-error < DUMP` after creating the role and database, compare row counts, then delete the scratch StatefulSet and its PVC. NetworkPolicies select `app=<STS>`, so the scratch pod is isolated; `exec` needs no network. Smoke-testing the application against it (`/ready`) needs a temporary copy of the app's config pointing at the scratch Service plus an allow rule; mark that optional.

Cutover:

```sh
kubectl -n NS scale deployment/<system>-web-server --replicas=0
kubectl -n NS delete job/<system>-db-mgmt --ignore-not-found
# final dump + pg_restore -l + row counts, as above
kubectl -n NS delete statefulset/STS
kubectl -n NS delete pvc/PVC                      # destroys the data; dump verified first
# set the image to postgres:TO in k8s/<realm>/03-postgres.yaml
kdd kapply 03-postgres
kubectl -n NS rollout status statefulset/STS --timeout=180s
kdd kapply 04-db-mgmt-job
kubectl -n NS wait --for=condition=complete job/<system>-db-mgmt --timeout=300s
kubectl -n NS exec -i STS-0 -- pg_restore -U postgres -d app_db --clean --if-exists --exit-on-error < DUMP
# row counts: identical to the final dump's counts
kubectl -n NS scale deployment/<system>-web-server --replicas=2
kubectl -n NS rollout status deployment/<system>-web-server --timeout=180s
```

Then verify `/health`, `/ready` and one business request.

Rollback is the same cutover with `FROM`: scale writers down, delete the StatefulSet **and its PVC** (the volume now holds `TO` data and `FROM` will not start on it), set the image back to `postgres:FROM`, `kdd kapply 03-postgres`, db-mgmt, restore the pre-cutover `DUMP`, scale up. Writers were stopped before the final dump, so nothing is lost. Decide before the window; rollback after writes resumed on `TO` loses those writes.

## Dev initialization flow

1. Connect with the root URL, create `app_db` / `app_user` if absent.
2. Apply the latest schema (from `sql/dev_initial/` or the latest schema dump).
3. Load seed data, or restore the anonymized dump if available.

## Data protection

- Never copy production data to dev unanonymized.
- Separate buckets (and retention) for `prod-storage` and `dev-storage`.
- Access to production backups is restricted to the backup role and the operations team.

## Local access

```sh
kubectl port-forward svc/rust10x-db 5432:5432 -n rust10x-web-app
psql "postgres://app_user:<password>@localhost:5432/app_db"
```
