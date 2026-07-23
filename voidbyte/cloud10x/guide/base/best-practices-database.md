# Database Best Practices

Best practices for database management, migrations, and operations in the rust10x architecture.

## Overview

The database strategy separates concerns between development (fast iteration) and production (reliability, backups). Drop-based upgrades provide a structured migration path while treating the production database as the single source of truth.

## Architecture

### Development vs. Production

| Aspect | Development | Production |
|--------|-------------|------------|
| **Runtime** | PostgreSQL StatefulSet in K8s | Cloud Managed (RDS/CloudSQL) |
| **Initialization** | Latest schema + anonymized data | Schema snapshot + incremental drops |
| **Migrations** | Replay all from scratch | Drop-based upgrades only |
| **Backups** | Optional | Automated, multi-AZ |
| **Access** | Direct via port-forward | Via application only |

### Connection Pattern

```yaml
# db-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: rust10x-db-secret
  namespace: rust10x-web-app
type: Opaque
immutable: true
stringData:
  SERVICE_DB_URL: "postgres://app_user:dev_only_pwd@rust10x-db:5432/app_db"
  SERVICE_PG_ROOT_URL: "postgres://postgres:welcome@rust10x-db:5432/postgres"
```

```rust
// In Rust code
let db_url = std::env::var("SERVICE_DB_URL")?;
let pool = sqlx::PgPool::connect(&db_url).await?;
```

## Drop-Based Upgrade Strategy

### Concept

Instead of replaying all migrations from the beginning of time, the production database is the single source of truth. Upgrades are organized into "drops" — versioned bundles of schema and data changes.

Drops are stored in a directory structure like `upgrades/drop-{NNNN}/`, where each drop contains ordered SQL migration files (e.g., `001-add-orders-table.sql`, `002-migrate-data.sql`). Old drops are archived in git history but removed from the active `upgrades/` directory.

### Upgrade Process

The drop upgrade process follows these steps in order:

1. **Backup Production DB**: Run `pg_dump` with custom format (`-Fc`), compress with gzip, and upload to S3 at `prod-storage:/prod-db-backups/prod-backup-{timestamp}-before-drop-{number}.dump.gzip`.

2. **Create Schema-Only Dump for Dev**: Run `pg_dump --schema-only --no-owner --no-acl`, compress with gzip, and upload to S3 at `dev-storage:/dev-db-backups/{timestamp}-dev-schema.sql.gzip`.

3. **Optional: Anonymize Data**: If needed, create an anonymized data dump and upload to `dev-storage:/dev-db-backups/{timestamp}-dev-anonymized.dump.gzip`.

4. **Apply Drop Upgrade**: Run all SQL migration files in `upgrades/drop-{number}/` in alphabetical order, wrapped in a single database transaction. On failure, the transaction rolls back automatically.

### Naming Conventions

| Artifact | Path Pattern |
|----------|-------------|
| Production backup | `prod-storage:/prod-db-backups/prod-backup-{YYYY-MM-DD-HH-MM}-before-drop-{NNNN}.dump.gzip` |
| Dev schema | `dev-storage:/dev-db-backups/{YYYY-MM-DD-HH-MM}-dev-schema.sql.gzip` |
| Dev anonymized | `dev-storage:/dev-db-backups/{YYYY-MM-DD-HH-MM}-dev-anonymized.dump.gzip` |

## Database Management Service (db-mgt)

### Responsibilities

The `db-mgt` service is a Rust CLI tool with five commands: `init`, `upgrade`, `backup`, `schema-dump`, and `anonymize`.

```rust
// crates/services/db-mgt/Cargo.toml
[dependencies]
clap = { version = "4", features = ["derive"] }
tokio = { version = "1", features = ["full"] }

// crates/services/db-mgt/src/main.rs
use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "db-mgt")]
#[command(about = "Database management utility")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize a fresh development database
    Init,
    /// Apply a numbered drop upgrade to production
    Upgrade,
    /// Create a production backup
    Backup,
    /// Dump schema-only snapshot for development
    SchemaDump,
    /// Anonymize and dump production data for dev use
    Anonymize,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init => init_database().await?,
        Commands::Upgrade => run_drop_upgrade().await?,
        Commands::Backup => backup_production().await?,
        Commands::SchemaDump => dump_schema_for_dev().await?,
        Commands::Anonymize => anonymize_and_dump().await?,
    }

    Ok(())
}
```

### Initialization Flow

The `init` command sets up a fresh development database:

1. Connect as root user and check if the `app_db` database exists.
2. Create `app_db` and `app_user` if they do not exist (using dev-only credentials).
3. Download the latest schema dump from dev storage and apply it.
4. If an anonymized data dump is available, restore it into the database.

```rust
async fn init_database() -> Result<()> {
    // 1. Check if database exists
    let root_pool = create_root_pool().await?;

    // 2. Create app database and user if not exists
    sqlx::query("CREATE DATABASE app_db").execute(&root_pool).await.ok();
    sqlx::query("CREATE USER app_user WITH PASSWORD 'dev_only_pwd'")
        .execute(&root_pool).await.ok();

    // 3. Apply latest schema from dev storage
    let schema = download_latest_schema().await?;
    let app_pool = create_app_pool().await?;
    sqlx::query(&schema).execute(&app_pool).await?;

    // 4. Load anonymized data if available
    if let Ok(dump) = download_anonymized_dump().await {
        restore_from_dump(&dump).await?;
    }

    Ok(())
}
```

### Drop Upgrade Flow

The `upgrade` command applies a numbered drop to production:

1. Create a pre-upgrade backup of production.
2. Read all `.sql` files from `upgrades/drop-{DROP_NUMBER}/`, sort them alphabetically.
3. Execute each file in order within a single database transaction.
4. Commit the transaction if all files succeed; otherwise, it rolls back.
5. Create a post-upgrade schema dump for development use.

```rust
async fn run_drop_upgrade() -> Result<()> {
    let drop_number = std::env::var("DROP_NUMBER")?;
    let upgrade_dir = format!("upgrades/drop-{}/", drop_number);

    // 1. Pre-upgrade backup
    let backup_path = backup_production().await?;
    println!("Backup created: {}", backup_path);

    // 2. Apply migrations in order
    let mut files = fs::read_dir(&upgrade_dir)?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension() == Some("sql".as_ref()))
        .collect::<Vec<_>>();
    files.sort();

    let pool = create_app_pool().await?;
    let mut tx = pool.begin().await?;

    for file in files {
        let sql = fs::read_to_string(&file)?;
        sqlx::query(&sql).execute(&mut *tx).await?;
    }

    tx.commit().await?;

    // 3. Post-upgrade schema dump for dev
    dump_schema_for_dev().await?;

    Ok(())
}
```

## Backup Strategy

### Production Backup

Production backups use `pg_dump -Fc` (custom format) for smaller file sizes and faster restore times. The output is piped through gzip and uploaded to S3.

```rust
async fn backup_production() -> Result<String> {
    let timestamp = chrono::Utc::now().format("%Y-%m-%d-%H-%M");
    let drop_number = std::env::var("DROP_NUMBER").unwrap_or_default();
    let filename = format!(
        "prod-backup-{}-before-drop-{}.dump.gzip",
        timestamp, drop_number
    );

    // pg_dump with custom format, gzip, upload to S3
    let output = Command::new("pg_dump")
        .args(&[
            "-Fc",  // Custom format
            "-f", "-",
            &std::env::var("SERVICE_PG_ROOT_URL")?,
        ])
        .output()?;

    let compressed = gzip_compress(&output.stdout)?;
    upload_to_s3("prod-storage", &format!("prod-db-backups/{}", filename), &compressed).await?;

    Ok(filename)
}
```

### Schema-Only Dump for Development

Development schema dumps are created with `--schema-only`, `--no-owner`, and `--no-acl` flags to make them portable across environments. These are also compressed and uploaded to S3.

```rust
async fn dump_schema_for_dev() -> Result<String> {
    let timestamp = chrono::Utc::now().format("%Y-%m-%d-%H-%M");
    let filename = format!("{}-dev-schema.sql.gzip", timestamp);

    let output = Command::new("pg_dump")
        .args(&[
            "--schema-only",
            "--no-owner",
            "--no-acl",
            "-f", "-",
            &std::env::var("SERVICE_PG_ROOT_URL")?,
        ])
        .output()?;

    let compressed = gzip_compress(&output.stdout)?;
    upload_to_s3("dev-storage", &format!("dev-db-backups/{}", filename), &compressed).await?;

    Ok(filename)
}
```

## Kubernetes Job for db-mgt

The `db-mgt` service runs as a Kubernetes Job, not a long-running service. It pulls configuration from a ConfigMap and secrets from two separate Secret resources.

```yaml
# db-mgmt-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: rust10x-db-mgmt
  namespace: rust10x-web-app
spec:
  backoffLimit: 3
  activeDeadlineSeconds: 300
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: db-mgmt
          image: k3d-rust10x-reg.localhost:5000/rust10x-db-mgmt:0.1.0
          envFrom:
            - configMapRef:
                name: rust10x-config
            - secretRef:
                name: rust10x-auth-secret
            - secretRef:
                name: rust10x-db-secret
          securityContext:
            runAsNonRoot: false
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
```

Run as a one-off job:

```bash
kubectl apply -f db-mgmt-job.yaml
kubectl logs job/rust10x-db-mgmt -n rust10x-web-app
```

## PostgreSQL StatefulSet

Development uses a single-replica PostgreSQL StatefulSet with a persistent volume for data storage.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rust10x-db
  namespace: rust10x-web-app
spec:
  serviceName: rust10x-db
  replicas: 1
  selector:
    matchLabels:
      app: rust10x-db
  template:
    metadata:
      labels:
        app: rust10x-db
    spec:
      containers:
        - name: postgres
          image: postgres:18
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: rust10x-postgres-secret
                  key: POSTGRES_ROOT_PASSWORD
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/18/data
          livenessProbe:
            tcpSocket:
              port: 5432
            initialDelaySeconds: 10
            periodSeconds: 10
```

### PostgreSQL Secrets

Database credentials are stored in an immutable Secret.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rust10x-postgres-secret
  namespace: rust10x-web-app
type: Opaque
immutable: true
stringData:
  POSTGRES_DB: app_db
  POSTGRES_USER: app_user
  POSTGRES_PASSWORD: dev_only_pwd
  POSTGRES_ROOT_PASSWORD: welcome
```

## Development Workflow

### Starting Fresh

```bash
# 1. Apply manifests
kubectl apply -f k8s/dev/00-namespace.yaml
kubectl apply -f k8s/dev/postgres-secret.yaml
kubectl apply -f k8s/dev/postgres-deployment.yaml
kubectl apply -f k8s/dev/postgres-service.yaml

# 2. Wait for PostgreSQL to be ready
kubectl wait --for=condition=ready pod -l app=rust10x-db -n rust10x-web-app

# 3. Run db-mgt init job
kubectl apply -f k8s/dev/db-mgmt-job.yaml

# 4. Verify
kubectl logs job/rust10x-db-mgmt -n rust10x-web-app
```

### Port-Forward for Local Access

```bash
kubectl port-forward svc/rust10x-db 5432:5432 -n rust10x-web-app
# Connect via: psql postgres://app_user:dev_only_pwd@localhost:5432/app_db
```

## Tips

- **Never replay all migrations in production** — use drop-based upgrades from the latest schema snapshot.
- **Always backup before upgrading** — the backup is your rollback strategy.
- **Use transactions for drop upgrades** — rollback on failure prevents partial migrations.
- **Keep old drops in git history** but remove from active `upgrades/` directory.
- **Anonymize production data** for development to prevent PII leakage.
- **Use `pg_dump -Fc` (custom format)** for production backups — smaller and faster than plain SQL.
- **Use `--schema-only --no-owner --no-acl`** for dev schema dumps — portable across environments.
- **Store backups in separate S3 buckets** for prod and dev with different retention policies.
- **Test drop upgrades against a copy of production data** before applying to production.
- **Document each drop** with a `README.md` in the drop directory explaining rationale and rollback steps.
