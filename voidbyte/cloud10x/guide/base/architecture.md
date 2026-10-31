# Cloud Architecture

Principle: limit technology to what is strictly necessary. One main technology for 90% of cases; treat exceptions as exceptions.

## Layers (bottom to top)

1. **Cloud platform**: AWS, GCP, Azure, or mature on-prem Kubernetes.
2. **Kubernetes**: universal runtime for application services and most infrastructure services.
3. **Message bus**: Valkey (pub/sub, streams, cache). See `valkey.md`.
4. **Back-end services**: workers, ops jobs, internal APIs.
5. **Front-end services**: web UI, public APIs, SSE endpoints.
6. **Cloud-specific services**: CDN, object storage, managed database, analytics.

## Service placement

| Service | Dev / local | Production |
|---------|-------------|------------|
| Application services | Kubernetes | Kubernetes |
| PostgreSQL | StatefulSet | Managed (RDS, Cloud SQL) |
| Valkey | Kubernetes | Kubernetes |
| Object storage | MinIO or local | S3 / GCS / Azure Blob |
| Secrets | Plain Secrets with dev-only values | External Secrets / Vault / Sealed Secrets |
| CDN, analytics | none | Cloud-native |

Services reach infrastructure through the same Kubernetes Service name in every environment (`rust10x-db:5432`). Whether it is a StatefulSet or a managed database is deployment configuration, not code.

## Service roles

| Role | Scaling | Rules |
|------|---------|-------|
| Web server | Horizontal | Stateless. Reads config from env. |
| Job worker | Horizontal | One main job per service. Consumes a Valkey stream. |
| Ops job (`db-mgmt`) | Kubernetes Job | Migrations, backups, dumps. Never run inside app startup. |
| Ops singleton (`cmd-pod`) | `replicas: 1` | Optional long-lived DevOps service for interactive ops. |

## Communication

- Services talk through the message bus, not directly. Direct HTTP/gRPC between services couples failure and scaling.
- Per service, two streams: `{service}.queue` (work) and `{service}.done` (completion).
- Consumer groups give loose coupling, independent scaling and backpressure. Delivery is at-least-once: handlers are idempotent (`valkey.md`).
- The database is the system of record. Valkey is never one.

## One language

One main language across services, backend and frontend where possible:

- shared types without IDL layers (Protobuf, Thrift)
- shared business logic
- one toolchain: linters, formatters, test runner, base images
- a smaller team that stays in sync

## Environments

- `dev`: throwaway local cluster (minikube, k3d). Seeded data. Dev-only credentials.
- `staging`: production topology, anonymized data.
- `prod`: managed database, external secrets, `confirm_delete: true`, immutable image tags, NetworkPolicies enforced.

## Rules

- Kubernetes is the abstraction layer. Do not couple code to a cloud SDK unless it is a Layer 6 service.
- Design with the queue from day one. Retrofitting events is expensive.
- Start simple. Add components only when a measured need exists.
- Version everything: images, manifests, schema drops.
