# Kubernetes Best Practices

Best practices for deploying Rust services and infrastructure on Kubernetes, based on the rust10x architecture.

## Overview

Kubernetes is the universal runtime for all application and most infrastructure services. This guide covers manifest organization, security, resource management, and operational patterns.

## Manifest Organization

### File Naming Convention

Prefix files with two-digit numbers to control `kubectl apply` order:

- `00-namespace.yaml` — Namespace must be first
- `01-pod-security.yaml` — Security policies next
- `_conf.yaml` — ConfigMap (underscore = no order dependency)
- `auth-secret.yaml` — Secrets
- `db-secret.yaml`
- `postgres-secret.yaml`
- `postgres-deployment.yaml` — StatefulSet for database
- `postgres-service.yaml` — Service for database
- `valkey-deployment.yaml` — Deployment for cache/queue
- `valkey-service.yaml`
- `db-mgmt-job.yaml` — One-off database jobs
- `web-server-deployment.yaml` — Application deployments
- `web-server-service.yaml`
- `web-server-ingress.yaml` — Ingress last

### Namespace Definition

```yaml
# 00-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: rust10x-web-app
```

### Pod Security Standards

```yaml
# 01-pod-security.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: rust10x-web-app
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/warn: baseline
```

| Level | Description | Use Case |
|-------|-------------|----------|
| `privileged` | Unrestricted | Avoid in production |
| `baseline` | Minimal restrictions | **Recommended default** |
| `restricted` | Maximum security | Sensitive workloads |

## ConfigMap Pattern

```yaml
# _conf.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: rust10x-config
  namespace: rust10x-web-app
data:
  SERVICE_TOKEN_DURATION_SEC: "1800"
  SERVICE_WEB_FOLDER: web-folder/
  SERVICE_SQL_FOLDER: /service/sql/
```

Inject into pods via `envFrom`:

```yaml
envFrom:
  - configMapRef:
      name: rust10x-config
```

## Secrets Management

### Separate by Concern

| Secret | Purpose | Immutable |
|--------|---------|-----------|
| `auth-secret` | JWT signing keys | Yes |
| `db-secret` | App DB connection strings | Yes |
| `postgres-secret` | PostgreSQL credentials | Yes |

### Immutable Secrets

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rust10x-auth-secret
  namespace: rust10x-web-app
type: Opaque
immutable: true
stringData:
  SERVICE_TOKEN_KEY: "..."
  SERVICE_PWD_KEY: "..."
```

> **Why immutable?** Prevents accidental mutations. To change, delete and recreate.

### Never Commit Real Secrets

Use one of:
- **Sealed Secrets** (Bitnami)
- **External Secrets Operator** (sync from cloud secret managers)
- **HashiCorp Vault**
- **SOPS** (Mozilla)

## Database Deployment (StatefulSet)

Use `StatefulSet` (not `Deployment`) for databases to ensure:
- Stable network identity (predictable pod names)
- Ordered deployment and scaling
- Persistent volume per pod

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

### Database Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rust10x-db
  namespace: rust10x-web-app
spec:
  ports:
    - port: 5432
  selector:
    app: rust10x-db
```

## Valkey Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rust10x-valkey
  namespace: rust10x-web-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rust10x-valkey
  template:
    metadata:
      labels:
        app: rust10x-valkey
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
      containers:
        - name: valkey
          image: valkey/valkey:8.1.3-bookworm
          ports:
            - containerPort: 6379
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
```

### Valkey Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rust10x-valkey
  namespace: rust10x-web-app
spec:
  ports:
    - port: 6379
  selector:
    app: rust10x-valkey
```

## Application Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rust10x-web-server
  namespace: rust10x-web-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: rust10x-web-server
  template:
    metadata:
      labels:
        app: rust10x-web-server
    spec:
      containers:
        - name: web-server
          image: k3d-rust10x-reg.localhost:5000/rust10x-web-server:0.1.0
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: rust10x-config
            - secretRef:
                name: rust10x-db-secret
            - secretRef:
                name: rust10x-auth-secret
          securityContext:
            runAsNonRoot: false
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: ["ALL"]
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
```

### Application Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rust10x-web-server
  namespace: rust10x-web-app
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 8081
  selector:
    app: rust10x-web-server
```

## Security Context

Apply at both **pod** and **container** levels:

```yaml
spec:
  securityContext:              # Pod-level
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
  containers:
    - name: app
      securityContext:          # Container-level
        runAsNonRoot: false     # Set true when image supports it
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
```

| Field | Recommendation |
|-------|--------------|
| `runAsNonRoot` | `true` for production; `false` only for legacy |
| `allowPrivilegeEscalation` | Always `false` |
| `readOnlyRootFilesystem` | `true` when possible (requires emptyDir for tmp) |
| `capabilities.drop` | Always `["ALL"]` |
| `seccompProfile` | `RuntimeDefault` or custom profile |

## Resource Management

Always define requests and limits:

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

| Resource | Request | Limit | Purpose |
|----------|---------|-------|---------|
| CPU | 100m | 500m | Guaranteed baseline, burst to limit |
| Memory | 128Mi | 512Mi | Prevent OOM, allow growth |

> **Never set CPU limits without requests** — leads to unpredictable scheduling.

## Health Probes

### Liveness Probe

Detects when to restart a container:

```yaml
livenessProbe:
  tcpSocket:
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 3
```

### Readiness Probe

Detects when a pod is ready to receive traffic:

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3
```

### Startup Probe

For slow-starting containers (prevents premature liveness kills):

```yaml
startupProbe:
  httpGet:
    path: /health
    port: 8080
  failureThreshold: 30
  periodSeconds: 10
```

## Jobs for One-Off Tasks

```yaml
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

| Property | Value | Purpose |
|----------|-------|---------|
| `backoffLimit` | 3 | Retry failed runs |
| `activeDeadlineSeconds` | 300 | Hard timeout |
| `restartPolicy` | `OnFailure` | Don't restart on success |
| `ttlSecondsAfterFinished` | 86400 | Auto-delete after 24h |

## Ingress Configuration

### Development (HTTP)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rust10x-web-server
  namespace: rust10x-web-app
spec:
  rules:
    - host: api.rust10x.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: rust10x-web-server
                port:
                  number: 80
```

### Production (HTTPS with TLS)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rust10x-web-server
  namespace: rust10x-web-app
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
    - hosts:
        - api.rust10x.local
      secretName: rust10x-tls
  rules:
    - host: api.rust10x.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: rust10x-web-server
                port:
                  number: 80
```

## Network Policies

Restrict pod-to-pod communication:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-server-policy
  namespace: rust10x-web-app
spec:
  podSelector:
    matchLabels:
      app: rust10x-web-server
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: rust10x-db
      ports:
        - protocol: TCP
          port: 5432
    - to:
        - podSelector:
            matchLabels:
              app: rust10x-valkey
      ports:
        - protocol: TCP
          port: 6379
```

## Scaling Strategy

### Horizontal Pod Autoscaling (HPA)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: rust10x-web-server
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: rust10x-web-server
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

### Vertical Pod Autoscaling (VPA)

Use VPA in recommendation mode first, then switch to auto mode after tuning:

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: rust10x-web-server
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: rust10x-web-server
  updatePolicy:
    updateMode: "Auto"
```

### Cluster Autoscaling

Enable cluster auto-scaler for node-level scaling:

```yaml
# AWS EKS with Karpenter
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
```

### The Three Pillars

| Pillar | Tool | Purpose |
|--------|------|---------|
| **Metrics** | Prometheus + Grafana | System health, resource usage |
| **Logs** | Loki / Fluentd + Elasticsearch | Application logs, debugging |
| **Traces** | Jaeger / Tempo | Distributed request tracing |

### Essential Metrics to Track

- Request latency (p50, p95, p99)
- Error rate (4xx, 5xx)
- Throughput (requests/sec)
- Resource utilization (CPU, memory)
- Queue depth (Valkey stream pending items)
- Database connection pool usage

## Pod Disruption Budget

Ensure minimum availability during node maintenance:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: rust10x-web-server
  namespace: rust10x-web-app
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: rust10x-web-server
```

## Tips

- **Use numbered prefixes** (`00-`, `01-`) to control `kubectl apply` order.
- **Always define a namespace** — never deploy to `default`.
- **Apply Pod Security Standards** at the namespace level.
- **Separate secrets by concern** for granular RBAC.
- **Mark secrets as immutable** when values never change.
- **Use StatefulSets for databases**, Deployments for stateless apps.
- **Always set resource requests and limits**.
- **Define all three probe types** (liveness, readiness, startup).
- **Use Jobs for migrations** — never in app startup.
- **Enable NetworkPolicies** for zero-trust pod communication.
- **Use PDBs** to prevent accidental downtime during cluster ops.
- **Comment out TLS ingress** in dev to avoid cert complexity.
- **Use `kubectl apply -f k8s/dev/`** with numbered files for ordered deployment.
