use axum::{Router, extract::State, http::StatusCode, routing::get};
use sqlx::{PgPool, postgres::PgPoolOptions};
use std::time::Duration;
use tokio::{
    net::TcpListener,
    signal::unix::{SignalKind, signal},
};
use tracing_subscriber::EnvFilter;

const ADDR: &str = "0.0.0.0:8081"; // pod port; Service, probes and NetworkPolicy use 8081

async fn health() -> &'static str {
    "ok"
}

// Readiness: the pool can reach the database. Liveness stays DB-free (/health).
async fn ready(State(pool): State<PgPool>) -> Result<&'static str, StatusCode> {
    sqlx::query("SELECT 1")
        .execute(&pool)
        .await
        .map(|_| "ok")
        .map_err(|e| {
            tracing::warn!("not ready: {e}");
            StatusCode::SERVICE_UNAVAILABLE
        })
}

async fn index() -> String {
    format!("{} {}", env!("CARGO_PKG_NAME"), env!("CARGO_PKG_VERSION"))
}

async fn shutdown() {
    let mut term = signal(SignalKind::terminate()).expect("install SIGTERM handler");
    tokio::select! {
        _ = term.recv() => {},
        _ = tokio::signal::ctrl_c() => {},
    }
    tracing::info!("shutting down");
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let url = std::env::var("SERVICE_DB_URL").expect("SERVICE_DB_URL");
    // Lazy: the server starts without the database; /ready reports 503 until it is reachable.
    let pool = PgPoolOptions::new()
        .max_connections(5)
        .acquire_timeout(Duration::from_secs(3))
        .connect_lazy(&url)
        .expect("SERVICE_DB_URL is not a valid postgres url");

    let app = Router::new()
        .route("/health", get(health))
        .route("/ready", get(ready))
        .route("/", get(index))
        .with_state(pool);
    let listener = TcpListener::bind(ADDR).await.expect("bind");
    tracing::info!("listening on {ADDR}");
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown())
        .await
        .expect("serve");
}
