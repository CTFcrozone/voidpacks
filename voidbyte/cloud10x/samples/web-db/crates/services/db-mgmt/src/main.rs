use sqlx::{ConnectOptions, Connection, PgConnection, postgres::PgConnectOptions};
use std::{error::Error, str::FromStr};
use tracing_subscriber::EnvFilter;

const APP_USER: &str = "app_user";
const APP_DB: &str = "app_db";

// One-shot, idempotent: ensures role `app_user` (password from env) and database `app_db`.
// Statements run outside a transaction (CREATE DATABASE requires it). Secrets are never logged:
// statement logging is off, and only the names above appear in log lines.
#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let root_url = std::env::var("SERVICE_PG_ROOT_URL")?;
    let password = std::env::var("SERVICE_DB_APP_PASSWORD")?;
    let options = PgConnectOptions::from_str(&root_url)?.disable_statement_logging();
    let mut conn = PgConnection::connect_with(&options).await?;

    let role_exists: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = $1)")
            .bind(APP_USER)
            .fetch_one(&mut conn)
            .await?;
    // DDL cannot take bind parameters: let the server quote the identifier and the literal.
    let ddl: String = sqlx::query_scalar(
        "SELECT format('%s ROLE %I LOGIN PASSWORD %L', $1::text, $2::text, $3::text)",
    )
    .bind(if role_exists { "ALTER" } else { "CREATE" })
    .bind(APP_USER)
    .bind(&password)
    .fetch_one(&mut conn)
    .await?;
    sqlx::query(&ddl).execute(&mut conn).await?;
    tracing::info!("role {APP_USER} ensured");

    let db_exists: bool =
        sqlx::query_scalar("SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = $1)")
            .bind(APP_DB)
            .fetch_one(&mut conn)
            .await?;
    if !db_exists {
        sqlx::query(&format!("CREATE DATABASE {APP_DB} OWNER {APP_USER}"))
            .execute(&mut conn)
            .await?;
    }
    sqlx::query(&format!("ALTER DATABASE {APP_DB} OWNER TO {APP_USER}"))
        .execute(&mut conn)
        .await?;
    tracing::info!("database {APP_DB} ensured");
    Ok(())
}
