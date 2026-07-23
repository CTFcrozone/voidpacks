# Cloud Architecture Best Practices

Best practices for designing portable, scalable cloud applications.

## Overview

This architecture is designed for new applications destined to scale in **users** and **features**, while keeping managed complexity low and avoiding accidental complexity as much as possible.

> **Core Principle:** limit tech proliferation to what is strictly necessary. Choose one main technology for 90% of use cases and treat exceptions as outliers.

## Architecture Layers (Bottom to Top)

The architecture is organized into six layers, from infrastructure up to external interfaces:

1. **Cloud Platform** — AWS, GCP, Azure, or mature on-premise Kubernetes
2. **Kubernetes Runtime** — Container orchestration for all services
3. **Queue & Message Bus (Valkey/Redis)** — Pub/sub, job queues, caching
4. **Back-End Services** — cmd-pod, job workers, internal APIs
5. **Front-End Services** — Web UI, mobile APIs, external API gateways
6. **Cloud-Specific Services** — CDN, object storage, big data, managed databases

## 1. Cloud Platform

### Requirements

- Robust, mature cloud platform
- Strong Kubernetes support
- Node auto-scaling capabilities (preferred)

### Supported Platforms

| Platform | Kubernetes Service | Notes |
|----------|-----------------|-------|
| AWS | EKS | Mature, widely adopted |
| GCP | GKE | Excellent GKE Autopilot |
| Azure | AKS | Good Azure integration |
| On-Premise | Self-managed K8s | Requires mature infrastructure team |

### Best Practice

Use Kubernetes as the **universal runtime** for all application services and most infrastructure services. This maximizes portability across cloud providers.

## 2. Kubernetes Runtime

### Service Placement Strategy

| Service Type | Dev/Staging | Production | Rationale |
|-------------|-------------|------------|-----------|
| Application Services | K8s | K8s | Universal runtime |
| Database | K8s (StatefulSet) | Cloud Managed (RDS/CloudSQL) | Dev simplicity vs. prod reliability |
| Cache/Queue (Valkey) | K8s | K8s | Better control and cloud portability |
| Object Storage | MinIO/Local | S3/GCS/Azure Blob | Cost and durability |

### Key Advantage

Kubernetes **Endpoint** support abstracts service access. Whether a database runs as a K8s StatefulSet or a cloud-managed service, other services access it via the same Kubernetes Service endpoint. This makes the choice purely a deployment configuration decision.

```yaml
# Same access pattern regardless of backend implementation
env:
  - name: SERVICE_DB_URL
    valueFrom:
      secretKeyRef:
        name: rust10x-db-secret
        key: SERVICE_DB_URL
# Value: postgres://app_user:dev_only_pwd@rust10x-db:5432/app_db
```

## 3. Queue & Message Bus

### Design Philosophy

This architecture is **heavily designed with a queue/message bus from the start** (not as an afterthought). Use Valkey (Redis fork) as the infrastructure pub/sub service.

### Valkey Usage Patterns

| Pattern | Purpose | Persistence |
|---------|---------|-------------|
| **Pub/Sub** | Real-time notifications (SSE) | None (fire-and-forget) |
| **Streams** | Job queues, event sourcing | Persistent |
| **Lists** | Simple task queues | Persistent |
| **Key-Value** | Caching, session storage | Configurable |

> **Important:** Valkey/Redis should **NOT** be used as a persistent store. Use it only for pub/sub, queues, and caching. Split caching into a separate Valkey instance if queue performance is critical.

### Why Valkey Over Redis?

- **Open Source:** BSD-3-Clause license (no proprietary restrictions)
- **Community-driven:** Linux Foundation project
- **Drop-in replacement:** Compatible with Redis protocols and clients
- **Future-proof:** Avoids Redis licensing changes

## 4. Back-End Services

### Service Categories

#### cmd-pod (Singleton DevOps Service)

A **singleton** service in the Kubernetes environment to perform all DevOps/CI-CD operations.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cmd-pod
  namespace: rust10x-web-app
spec:
  replicas: 1  # Always singleton
  selector:
    matchLabels:
      app: cmd-pod
  template:
    spec:
      containers:
        - name: cmd-pod
          image: your-registry/cmd-pod:latest
```

**Responsibilities:**
- Database migrations and schema management
- Backup operations
- One-off administrative tasks
- CI/CD pipeline execution

#### Horizontal Services (Job Workers)

Services that can scale horizontally and should have **one main job**.

**Communication Pattern:**

All services coordinate via the message bus using two queues per service:

- **Command Queue:** `{service_name}.queue` — work to be done
- **Done Queue:** `{service_name}.done` — job completion status

Services communicate by writing to a Valkey Stream and reading via consumer groups. This provides loose coupling, independent scaling, natural backpressure, and exactly-once processing.

## 5. Front-End Services

Services that interface the system to external consumers:

| Interface Type | Technology | Example |
|---------------|------------|---------|
| Web UI | React/Vue/Svelte + TypeScript | `frontends/web/` |
| Mobile API | REST/GraphQL | `services/api-gateway/` |
| External API | REST with OpenAPI | `services/web-server/` |
| Server-Sent Events | HTTP/1.1 persistent connection | Real-time notifications |

## 6. Cloud-Specific Services

While 100% cloud portability is appealing, leveraging cloud-native services adds great scalability.

| Service | Cloud Option | K8s Alternative | Recommendation |
|---------|-------------|-----------------|----------------|
| CDN | CloudFront/Cloud CDN | Nginx Ingress | Use cloud CDN in production |
| Object Storage | S3/GCS/Azure Blob | MinIO | Cloud for prod, local for dev |
| Big Data | BigQuery/Athena/Redshift | Spark on K8s | Use cloud for analytics |
| Database | RDS/CloudSQL/Spanner | PostgreSQL StatefulSet | Cloud for prod, K8s for dev |
| Secrets | AWS Secrets Manager | Sealed Secrets/Vault | Cloud for prod |

## Tech Stack Decisions

### Container

| Category | Main Choice | Exceptions |
|----------|------------|------------|
| **Main** | Docker + Alpine Linux | Lightweight, well-supported |
| **Exception 1** | Debian/Bookworm | Default for Rust projects |
| **Exception 2** | Ubuntu | Machine learning tasks |

### Why Mono-Language?

Using one main language across microservices, backend, and frontend:

1. **Shared Logic Code** — Reuse business logic across services
2. **Shared Types** — Native type system communication without ProtoBuf/Thrift
3. **Team Focus** — Smaller team in sync vs. larger team dispersed
4. **Tooling Uniformity** — One set of linters, formatters, test frameworks

> **Social Engineering Note:** This is often the hardest point to accomplish. There is always pressure to make all preferred languages "first-class citizens." For high-velocity development, **focus and discipline are paramount**.

## Service Communication Patterns

### Anti-Pattern: Direct Service-to-Service

Direct HTTP or gRPC calls between services create tight coupling, cascading failures, and make independent scaling difficult.

### Pattern: Event Bus via Valkey Streams

Services communicate by writing events to Valkey Streams and consuming via consumer groups. This provides:

- Loose coupling between services
- Independent horizontal scaling
- Natural backpressure handling
- Exactly-once processing with consumer groups

## Database Strategy

### Development

Use a PostgreSQL StatefulSet in Kubernetes for development. Benefits include easy reset, fast iteration, and local data persistence via PVC.

### Production

Use a cloud-managed database (RDS, CloudSQL, etc.) for production. Benefits include automated backups, multi-AZ replication, point-in-time recovery, and managed patches and upgrades.

### Migration Strategy (Drop-Based Upgrades)

The production database is the single source of truth. Upgrades follow this process:

1. **Backup** — Run `pg_dump` with custom format, compress with gzip, and upload to S3 at `prod-storage:/prod-db-backups/prod-backup-{timestamp}-before-drop-{number}.dump.gzip`
2. **Schema-only dump** — Run `pg_dump --schema-only --no-owner --no-acl`, compress, and upload to `dev-storage:/dev-db-backups/{timestamp}-dev-schema.sql.gzip`
3. **Optional: Anonymized dump** — Create an anonymized data dump and upload to `dev-storage:/dev-db-backups/{timestamp}-dev-anonymized.dump.gzip`

### Development Database Seeding

1. Access dev storage (S3-compatible)
2. Download latest schema dump
3. Download anonymized database (if available)
4. Initialize local PostgreSQL StatefulSet

## Tips

- **Start simple, scale later** — Don't over-engineer for hypothetical scale.
- **Use Kubernetes as the abstraction layer** — It makes cloud migration trivial.
- **Design with the queue from day one** — Retrofitting event-driven architecture is painful.
- **Keep the database close to the app in dev** — Use StatefulSet for fast iteration.
- **Use cloud-managed databases in production** — Let experts handle backups and replication.
- **One language, 90% of the time** — Resist the urge to polyglot.
- **Version everything** — Images, manifests, and infrastructure code.
