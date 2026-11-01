# Kubernetes

Rules for manifests in a KDD system. Full reference manifests: `samples/web-app/k8s/`.

## Layout

| Track | Directory | Shape |
|-------|-----------|-------|
| Per-block (minikube) | `k8s/dev/` | One file per block (`db.yaml`, `queue.yaml`, `web-server.yaml`) plus `_`-prefixed shared files. `default` namespace. Applied by `kdd kapply`. |
| Numbered (k3d / k3s / shared clusters) | `k8s/<realm>/` (references: `k8s/dev_k3d/`) | Numbered files, dedicated namespace. Applied in stages by `kdd kapply <names>` (`k3d.sh`). |

Both tracks are flat (kdd does not recurse) and templated (`{{registry}}`, `{{system}}`, `{{image_tag}}`). Numbered order (file stems sort lexically = apply order):

```
00-namespace  01-config  02-secrets  03-postgres  04-valkey
05-db-mgmt-job  06-web-server  07-ingress  08-network-policy
```

- Every pod template of a kdd-managed service carries `run: "{{system}}-{block}"` next to `app` (needed by `kdd klog` / `kdd kexec`, see `kdd.md`).
- kdd does not wait for readiness. The `db-mgmt` Job runs only after PostgreSQL is ready (`kubectl rollout status statefulset/<db>`), so apply in stages.
- Throwaway local clusters may use `default`. Every shared or persistent cluster uses a dedicated namespace. Never deploy to `default` there.

## Namespace and Pod Security

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: rust10x-web-app
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/audit: restricted
```

- Enforce `baseline`, warn and audit `restricted`. Fix every warning, then enforce `restricted` in production.
- One Namespace object per namespace. Do not redeclare it in a second file.

## Config and secrets

- `ConfigMap`: non-sensitive settings only. Inject with `envFrom`.
- `Secret`: everything sensitive, including connection strings that embed passwords (`SERVICE_DB_URL`). Never put credentials in a ConfigMap.
- Split secrets by concern (`auth-secret`, `db-secret`, `postgres-secret`) so RBAC and rotation stay granular.
- `immutable: true` on stable secrets. To change one: delete, recreate, roll the Deployment.
- Committed manifests carry placeholders (`REPLACE_ME`) only. Real values come from External Secrets Operator, Vault, Sealed Secrets or SOPS.
- Never commit private keys, including self-signed TLS keys. Generate locally (`mkcert`, `openssl`) or issue with cert-manager.

## Workloads

| Kind | Use for |
|------|---------|
| `Deployment` | Stateless services, Valkey |
| `StatefulSet` | PostgreSQL (dev), anything needing stable identity and storage |
| `Job` | Migrations, backups, dumps |

- A `StatefulSet` mounting storage must declare `volumeClaimTemplates`. A `volumeMounts` entry without a matching volume is rejected.
- Jobs: `backoffLimit`, `activeDeadlineSeconds` and `ttlSecondsAfterFinished` always set.
- Labels on every object: `app` (matches the selector). Add `app.kubernetes.io/part-of: <system>` for tooling.
- Pods that serve traffic run `replicas >= 2` in production.

## Security context

Pod level:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile: { type: RuntimeDefault }
```

Container level:

```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities: { drop: ["ALL"] }
```

- `runAsNonRoot: true` everywhere the image supports it. `false` is a documented exception, not a default.
- `readOnlyRootFilesystem: true` plus `emptyDir` for writable paths (`/tmp`).
- No `privileged`, `hostPath`, `hostNetwork`, or host `/sys` writes in shared clusters. Disable transparent huge pages at the node level, not from a pod.

## Resources and probes

- Every container sets `requests` and `limits` for CPU and memory. Never a limit without a request.
- Starting point for a Rust service: requests `100m` / `128Mi`, limits `500m` / `512Mi`. Tune from metrics.
- `readinessProbe` gates traffic. `livenessProbe` restarts. `startupProbe` covers slow starts.
- Prefer an HTTP health endpoint (`/health`). Use `tcpSocket` only when none exists. PostgreSQL: `exec` with `pg_isready`.

## Services and ports

- Default `ClusterIP`. `LoadBalancer` only for local dev behind `minikube tunnel`; never expose PostgreSQL or Valkey externally.
- Keep three numbers consistent: Service `port`, Service `targetPort`, container `containerPort` / app listen port. Example: `80` → `8081` → `8081`.
- NetworkPolicy ports are the **pod** (target) port, not the Service port.

## Ingress and TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rust10x-web-server
  namespace: rust10x-web-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
    - hosts: [api.example.com]
      secretName: rust10x-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: rust10x-web-server, port: { number: 80 } }
```

- Dev: HTTP, host such as `api.rust10x.local` mapped in `/etc/hosts`.
- Staging/prod: TLS only; certificates from cert-manager. Add the controller-specific entrypoint annotation (Traefik `websecure`, etc.).

## NetworkPolicy (default deny)

Pattern: one `default-deny` for ingress and egress, then explicit allows. Policies are additive.

Every connection needs **both** halves: egress allowed on the client and ingress allowed on the server.

| Flow | Client egress | Server ingress |
|------|---------------|----------------|
| DNS | all pods → `kube-dns` (53 UDP/TCP) | n/a |
| Ingress controller → web-server | n/a | from controller namespace, port 8081 |
| web-server → PostgreSQL | web-server → db 5432 | db from web-server 5432 |
| web-server → Valkey | web-server → valkey 6379 | valkey from web-server 6379 |
| db-mgmt → PostgreSQL | db-mgmt → db 5432 | db from db-mgmt 5432 |

- Namespace selectors use the built-in label `kubernetes.io/metadata.name: <ns>`. Do not invent a `name:` label.
- Combine `namespaceSelector` and `podSelector` in one `to`/`from` entry to AND them.
- Common failures: allowing Service port instead of pod port; allowing client egress but forgetting server ingress; no DNS egress.
- Requires a CNI that enforces NetworkPolicy (k3s does; verify on managed clusters).

## Scaling and availability

- `HorizontalPodAutoscaler` (`autoscaling/v2`): CPU target ~70%, `minReplicas >= 2`.
- `PodDisruptionBudget` for every multi-replica service: `minAvailable: 1`.
- VPA in recommendation mode first. Cluster/node autoscaling per cloud (Cluster Autoscaler, Karpenter).

## Observability

| Pillar | Tooling |
|--------|---------|
| Metrics | Prometheus + Grafana |
| Logs | Loki, or Fluentd + Elasticsearch |
| Traces | Tempo or Jaeger |

Track: request latency (p50/p95/p99), error rate, throughput, CPU/memory, Valkey stream pending count, database pool usage.

## Checklist

- [ ] Dedicated namespace with Pod Security labels
- [ ] No credentials in ConfigMaps; no real secrets in git
- [ ] Non-root, read-only root FS, all capabilities dropped
- [ ] Requests, limits and probes on every container
- [ ] Images templated and version-tagged; no `latest`
- [ ] Port numbers consistent across Service, Deployment and NetworkPolicy
- [ ] Default-deny NetworkPolicy with explicit allows for both sides
- [ ] PDB and HPA on scaled services

The rules in this guide are enforced by `lint.py` (see `lint.md`).
