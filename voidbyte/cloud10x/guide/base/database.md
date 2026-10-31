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
