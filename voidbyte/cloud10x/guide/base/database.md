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

Drops (above) change the schema. A **major version** change (18 to 19) is different: PostgreSQL refuses to start a new major on a data directory initialized by the old one, so bumping the image on the existing volume crash-loops the pod. The volume must be recreated and the data restored from a dump.

The scripts below are the procedure. A runbook copies them verbatim and changes only the values in the variables block. Tested: the dump, gating, restore, ownership, row counts and rollback flow ran against a real PostgreSQL server with a stubbed `kubectl`/`kdd`, including a failing dump that aborts before anything is deleted. Not tested: a live cluster (PVC deletion, the old-volume crash-loop, pod scheduling).

Rules:

- Stream through `kubectl exec`: dumps go to a local file with `>`, restores read stdin with `exec -i`. No port-forward, no local client versions to match, no password on a command line, no file in the pod (`/tmp` there is an `emptyDir`). Use `-i`, never `-it`, in scripts. The official image trusts the local socket, so `-U postgres` needs no password.
- `set -euo pipefail` in every phase: a failing step stops the script before the next one. For the same reason never paste a phase into an interactive shell (the next error would close your terminal). Save the variables block as `vars.sh` and each phase as `phaseA.sh`, `phaseB.sh`, `phaseC.sh`, then run `bash -c 'source vars.sh; source phaseA.sh'`.
- Do not commit the image change until the cutover is verified. Phase B edits `03-postgres.yaml` in the working tree and phase C reverts it with `git checkout`; a committed change would make the rollback a no-op.
- If phase A stops after applying the rehearsal (for example the target image does not exist), clean up before retrying: `kubectl -n NS delete -f /tmp/<STS>-rehearsal.yaml; kubectl -n NS delete pvc/data-<STS>-rehearsal-0`.
- **Nothing is deleted before the final dump is verified**: it is written to `$DUMP.partial`, restored into the rehearsal instance, and its row counts compared with the source. Only then it replaces `$DUMP`. Deleting the PVC destroys the only copy of the data on the cluster.
- Apply with `kdd kapply <stem>`, never `kubectl apply -f k8s/...` on source files: they are templates (`{{system}}`, `{{image_tag}}`) and only the rendered `.out/` files are valid YAML. The rehearsal manifest is generated from the rendered file; check it holds only the db objects (Service, StatefulSet) before applying.
- Roles come from db-mgmt and the secrets, not from the dump. Precondition: `\du` lists only `postgres` and `app_user`; otherwise also dump `pg_dumpall --globals-only` and replay it first.
- Restore keeps ownership (no `--no-owner`): db-mgmt creates `app_user` and `app_db` first, so objects land owned by `app_user`.
- This procedure has downtime. If downtime is not allowed, stop: the answer is logical replication or a managed service. Say so under "Open questions" instead of improvising.
- Rehearsal needs no NetworkPolicy change: its pods are not selected by the allow rules, and `kubectl exec` does not use the network. Smoke-testing the application against it is optional and needs a temporary config and allow rule.
- After phase B starts, a failure at or after the PVC deletion is recovered from `$DUMP` (verified); do not re-run phase A.

Preconditions (run, read the output):

```sh
kubectl -n NS exec STS-0 -- psql -U postgres -At -c '\du'     # only postgres and app_user
docker manifest inspect postgres:TO-<variant> >/dev/null && echo exists
```

Variables (values come from the project's manifests; the names below are the sample's):

```sh
NS=rust10x-web-app
SYS=rust10x
STS=$SYS-db
PVC=data-$STS-0                      # <volumeClaimTemplates name>-<STS>-<ordinal>
WEB=$SYS-web-server
JOB=$SYS-db-mgmt
FROM=18; TO=19
SRC=k8s/dev_k3s                      # source manifests (templates)
OUT=k8s/dev_k3s/.out/dev_k3d         # rendered by kdd for the current realm
DUMP=/tmp/rust10x-pg18-pre-upgrade.dump
K="kubectl -n $NS"
counts() {   # per-table row counts of app_db in pod $1
  $K exec -i "$1" -- psql -U postgres -d app_db -At -f - <<'SQL'
SELECT format('SELECT %L, count(*) FROM %s', c.oid::regclass, c.oid::regclass) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE c.relkind = 'r' AND n.nspname NOT IN ('pg_catalog','information_schema') ORDER BY 1 \gexec
SQL
}
```

Phase A - backup and rehearsal (no production change; leaves the rehearsal instance running):

```sh
set -euo pipefail
# A. Backup and rehearsal. Changes nothing in production. Leaves the rehearsal instance running.
$K exec "$STS-0" -- pg_dump -U postgres -Fc app_db > "$DUMP.partial"
test -s "$DUMP.partial"
kdd ktemplate 03-postgres
sed -E "/serviceAccountName/! s/$STS/$STS-rehearsal/g; s|(image: postgres:)$FROM|\1$TO|" "$OUT/03-postgres.yaml" > "/tmp/$STS-rehearsal.yaml"
$K apply -f "/tmp/$STS-rehearsal.yaml"
$K rollout status "statefulset/$STS-rehearsal" --timeout=180s
$K exec -i "$STS-rehearsal-0" -- psql -U postgres -v ON_ERROR_STOP=1 <<'SQL'
CREATE ROLE app_user LOGIN;
CREATE DATABASE app_db OWNER app_user;
SQL
$K exec -i "$STS-rehearsal-0" -- pg_restore -U postgres -d app_db --exit-on-error < "$DUMP.partial"
SRC_COUNTS=$(counts "$STS-0"); test -n "$SRC_COUNTS"
REH_COUNTS=$(counts "$STS-rehearsal-0")
test "$SRC_COUNTS" = "$REH_COUNTS"
mv "$DUMP.partial" "$DUMP"
echo "rehearsal OK: dump restores on postgres $TO with identical row counts"
```

Phase B - cutover (downtime):

```sh
set -euo pipefail
# B. Cutover. Requires phase A (rehearsal instance still running). Downtime starts here.
REPLICAS=$($K get "deployment/$WEB" -o jsonpath='{.spec.replicas}')
$K scale "deployment/$WEB" --replicas=0
$K delete "job/$JOB" --ignore-not-found
# final dump, verified by restoring it into the rehearsal instance before anything is deleted
$K exec "$STS-0" -- pg_dump -U postgres -Fc app_db > "$DUMP.partial"
test -s "$DUMP.partial"
$K exec -i "$STS-rehearsal-0" -- pg_restore -U postgres -d app_db --clean --if-exists --exit-on-error < "$DUMP.partial"
counts "$STS-0" > "$DUMP.counts"; test -s "$DUMP.counts"
counts "$STS-rehearsal-0" | diff - "$DUMP.counts"
mv "$DUMP.partial" "$DUMP"
# point of no return: the old data volume is destroyed
$K delete "statefulset/$STS"
$K delete "pvc/$PVC"
sed -i -E "s|(image: postgres:)$FROM|\1$TO|" "$SRC/03-postgres.yaml"
git diff -- "$SRC/03-postgres.yaml"
kdd kapply 03-postgres
$K rollout status "statefulset/$STS" --timeout=180s
kdd kapply 04-db-mgmt-job
$K wait --for=condition=complete "job/$JOB" --timeout=300s
$K exec -i "$STS-0" -- pg_restore -U postgres -d app_db --clean --if-exists --exit-on-error < "$DUMP"
counts "$STS-0" | diff - "$DUMP.counts"
$K scale "deployment/$WEB" --replicas="$REPLICAS"
$K rollout status "deployment/$WEB" --timeout=180s
$K delete -f "/tmp/$STS-rehearsal.yaml"
$K delete "pvc/data-$STS-rehearsal-0"
echo "cutover OK: now check /health, /ready and one business request"
```

Then verify: `curl -i http://<ingress-host>/health` and `/ready` both return `200 OK` with body `ok`, and one business request works.

Phase C - rollback to `FROM` (writes made on `TO` are lost; decide before the window):

```sh
set -euo pipefail
# C. Rollback to $FROM from the verified dump. Writers must be stopped; writes made on $TO are lost.
REPLICAS=$($K get "deployment/$WEB" -o jsonpath='{.spec.replicas}')
$K scale "deployment/$WEB" --replicas=0
$K delete "job/$JOB" --ignore-not-found
$K delete "statefulset/$STS"
$K delete "pvc/$PVC"                 # the volume holds $TO data; $FROM cannot start on it
git checkout -- "$SRC/03-postgres.yaml"
kdd kapply 03-postgres
$K rollout status "statefulset/$STS" --timeout=180s
kdd kapply 04-db-mgmt-job
$K wait --for=condition=complete "job/$JOB" --timeout=300s
test -s "$DUMP"
$K exec -i "$STS-0" -- pg_restore -U postgres -d app_db --clean --if-exists --exit-on-error < "$DUMP"
counts "$STS-0" | diff - "$DUMP.counts"
$K scale "deployment/$WEB" --replicas="$REPLICAS"
$K rollout status "deployment/$WEB" --timeout=180s
```

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
