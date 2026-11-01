# web-db-staging reference realm

Adds a `staging` realm to a project built from `../web-db/`: managed PostgreSQL (no in-cluster database, no db-mgmt Job), image by digest, TLS ingress with a cert-manager issuer. `add-realm.md` reproduces it with your parameters (`guide/base/scaffolding.md`, "Realm reference").

Files (new; nothing else in the project changes except two lines of `kdd.yaml`):

- `staging/kdd-staging.yaml`: the realm and its variables (`replicas`, `ingress_host`, `cert_issuer`, `db_cidr`, `web_server_digest`).
- `k8s/staging/`: the dev set with the in-cluster database and db-mgmt removed. Kept files keep their names and numbers (`00`, `01`, `05`, `06`, `07`); there is no secrets manifest.

`kdd.yaml` gains, in its first YAML document:

```yaml
overlays:
  - staging/kdd-staging.yaml
```

Values the operator supplies (examples here: `staging-example`, `registry.example.com`, `203.0.113.0/24`, `api.rust10x.example`, `letsencrypt-staging`, a zero digest):

- the kubectl context and registry host of the staging cluster;
- a Secret `rust10x-db-secret` with key `SERVICE_DB_URL`, provided by the secret store or operator;
- the managed database and its `app_user` / `app_db`, created out of band;
- `db_cidr`: the address range of the managed database (the NetworkPolicy allows egress to it only);
- a cert-manager ClusterIssuer named `cert_issuer`, and DNS for `ingress_host`;
- the image digests of the build being deployed (`web_server_digest`).

Verified in testing: the rendered set passes `lint.py` (11 objects, 0 findings) and the realm rules of `check.sh` (six deliberate violations each fail). Not verified: a deploy to a real cluster.
