# Valkey

Valkey (BSD-3-Clause, Linux Foundation) is the Redis-protocol message bus and cache. Any Redis client works (Rust: the `redis` crate).

> **Rule:** Valkey is never the system of record. Use it for pub/sub, queues (streams) and caching. The database owns durable state.

## Roles

| Role | Primitive | Durability | Use |
|------|-----------|------------|-----|
| Real-time notify | Pub/Sub | none (fire and forget) | SSE, UI refresh |
| Job queue | Streams + consumer groups | persistent if AOF on | Background work, service-to-service events |
| Simple queue | Lists | persistent if AOF on | Trivial FIFO |
| Cache | Keys with TTL | disposable | Sessions, derived data |

If queue throughput matters, run the cache on a **separate Valkey instance**.

## Streams

Two streams per service: `{service}.queue` (commands) and `{service}.done` (results).

```
XGROUP CREATE orders.queue workers $ MKSTREAM
XADD orders.queue MAXLEN ~ 100000 * payload '{"order_id":42}'
XREADGROUP GROUP workers worker-1 COUNT 10 BLOCK 5000 STREAMS orders.queue >
XACK orders.queue workers <entry-id>
XAUTOCLAIM orders.queue workers worker-1 60000 0-0 COUNT 10
```

| Command | Purpose |
|---------|---------|
| `XGROUP CREATE ... MKSTREAM` | Idempotent startup: create group, tolerate "already exists". |
| `XADD ... MAXLEN ~ N` | Append and trim approximately; bounds memory. |
| `XREADGROUP ... >` | Read new entries for this consumer. |
| `XACK` | Mark processed. Unacked entries stay pending. |
| `XAUTOCLAIM` | Reclaim entries from crashed consumers after the idle timeout. |

### Delivery semantics

- Consumer groups are **at-least-once**, not exactly-once. A crash between processing and `XACK` redelivers.
- Handlers must be idempotent: dedupe on a business key or entry id, or use a database unique constraint.
- Consumer name = pod name (stable per replica). Group name = service role.
- Poison messages: count deliveries (`XPENDING`), move to `{service}.dead` after N attempts.
- Always `XACK` after the side effect is committed, never before.

## Pub/Sub

- Subscribers must be connected when the message is published; offline subscribers lose it.
- Channel naming: `{domain}.{entity}.{id}` (e.g. `org.42.events`).
- Use for notifications. For anything that must not be lost, use a stream.

## Deployment

- `Deployment`, `replicas: 1`, `ClusterIP` Service `rust10x-valkey:6379`. Never `LoadBalancer`, never public.
- Image `valkey/valkey:<pinned-version>`. Run non-root, `allowPrivilegeEscalation: false`, drop `ALL`.
- Do not write to host `/sys` from an init container to disable transparent huge pages (needs privileged + `hostPath`). Fix at the node level; the container only logs a warning.
- Production: authentication (ACL user or `requirepass` from a Secret) and a NetworkPolicy that admits only the services that use it.
- Persistence for queues that must survive a restart: enable AOF and mount a PVC at `/data`. Without one, a restart empties every stream.
- Set `maxmemory` and an eviction policy per instance: `noeviction` for queues, `allkeys-lru` for caches.

Reference manifests: `samples/web-app/k8s/dev_k3s/04-valkey.yaml`, `samples/web-app/k8s/dev/queue.yaml`.

## Config

```
SERVICE_VALKEY_URL=redis://rust10x-valkey:6379
```

Read from env at startup; one client wrapper per process, multiplexed connections for commands, a dedicated connection per pub/sub subscription.

## Operations

- Monitor: stream length, pending count (`XPENDING`), consumer lag, memory, evictions, connected clients.
- Alert on pending entries older than the processing SLA and on memory near `maxmemory`.
- Trim streams on write (`MAXLEN ~`), not with a separate sweeper.

## Rules

- One main job per worker service; one stream pair per service.
- Idempotent handlers, ack after commit, trim on write.
- No business data that exists only in Valkey.
- No direct service-to-service calls where a stream fits.
