# Hardening lint

`samples/web-app/lint.py` turns the hardening rules of this pack into a gate. `check.sh` runs it on the rendered manifests (`.out/<realm>/`); it exits non-zero on any finding. Copy `lint.py` and `check.sh` into the project root unchanged.

```sh
python3 lint.py k8s/dev_k3s/.out/dev_k3d    # needs PyYAML (pacman -S python-yaml)
python3 lint.py --rules
```

## Rules

| Rule | Requirement |
|---|---|
| `pod-non-root` | runAsNonRoot: true (pod or every container) |
| `pod-explicit-uid` | runAsUser set and non-zero (pod or every container) |
| `pod-seccomp` | seccompProfile RuntimeDefault or Localhost |
| `pod-no-sa-token` | automountServiceAccountToken: false |
| `pod-sa-dedicated` | serviceAccountName set and not 'default' |
| `pod-no-host` | no hostNetwork/hostPID/hostIPC/hostPath |
| `ctr-no-priv-esc` | allowPrivilegeEscalation: false |
| `ctr-not-privileged` | privileged is not true |
| `ctr-readonly-root` | readOnlyRootFilesystem: true |
| `ctr-drop-all` | capabilities.drop contains ALL, nothing added |
| `ctr-resources` | requests and limits for cpu and memory |
| `ctr-image-tag` | image has a tag or digest, never latest |
| `ctr-probes` | readinessProbe and livenessProbe (long-running workloads) |
| `wl-run-label` | pod template has label 'run' (kdd klog/kexec) |
| `sts-volume-claim` | StatefulSet has volumeClaimTemplates |
| `deploy-pdb` | Deployment with replicas > 1 has a PodDisruptionBudget |
| `ns-pss` | Namespace has pod-security enforce, warn and audit labels |
| `netpol-default-deny` | namespace with workloads has a default-deny NetworkPolicy (Ingress+Egress) |
| `secret-tls-key` | no kubernetes.io/tls Secret with a private key in the repo |

## Waivers

A rule is waived only with an annotation on the workload (or its pod template), plus a comment saying why:

```yaml
metadata:
  annotations:
    lint.cloud10x/skip: "ctr-probes"   # one-shot tool, no long-running health
```

Waived findings are printed as `WAIVED` on every run, so they stay visible in CI. Do not waive `pod-non-root`, `ctr-drop-all` or `netpol-default-deny` to make a build pass; change the manifest.

## Scope

The linter checks structure, not behavior. It does not prove a NetworkPolicy allows the right ports, that a Secret holds good values, or that an image is free of CVEs. Those need a cluster test, a secrets process and an image scanner (see `ci.md`).
