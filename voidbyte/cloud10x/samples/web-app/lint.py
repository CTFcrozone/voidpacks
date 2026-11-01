#!/usr/bin/env python3
"""Hardening linter for rendered Kubernetes manifests (cloud10x pack).

Usage:  python3 lint.py <dir-with-rendered-yaml>      (non-recursive, *.yaml)
        python3 lint.py --rules                       (list rule ids)

Needs PyYAML (Arch: pacman -S python-yaml; Debian: apt install python3-yaml).
Exit 1 if any rule fails. Waive a rule with an annotation on the workload (or its
pod template):  lint.cloud10x/skip: "ctr-probes"   (comma separated, justify in a comment).
"""
import glob
import os
import sys

try:
    import yaml
except ImportError:
    sys.exit("lint.py needs PyYAML (pacman -S python-yaml | apt install python3-yaml)")

RULES = {
    "pod-non-root": "runAsNonRoot: true (pod or every container)",
    "pod-explicit-uid": "runAsUser set and non-zero (pod or every container)",
    "pod-seccomp": "seccompProfile RuntimeDefault or Localhost",
    "pod-no-sa-token": "automountServiceAccountToken: false",
    "pod-sa-dedicated": "serviceAccountName set and not 'default'",
    "pod-no-host": "no hostNetwork/hostPID/hostIPC/hostPath",
    "ctr-no-priv-esc": "allowPrivilegeEscalation: false",
    "ctr-not-privileged": "privileged is not true",
    "ctr-readonly-root": "readOnlyRootFilesystem: true",
    "ctr-drop-all": "capabilities.drop contains ALL, nothing added",
    "ctr-resources": "requests and limits for cpu and memory",
    "ctr-image-tag": "image has a tag or digest, never latest",
    "ctr-probes": "readinessProbe and livenessProbe (long-running workloads)",
    "wl-run-label": "pod template has label 'run' (kdd klog/kexec)",
    "sts-volume-claim": "StatefulSet has volumeClaimTemplates",
    "deploy-pdb": "Deployment with replicas > 1 has a PodDisruptionBudget",
    "ns-pss": "Namespace has pod-security enforce, warn and audit labels",
    "netpol-default-deny": "namespace with workloads has a default-deny NetworkPolicy (Ingress+Egress)",
    "secret-tls-key": "no kubernetes.io/tls Secret with a private key in the repo",
}
LONG = {"Deployment", "StatefulSet", "DaemonSet"}
WORKLOADS = LONG | {"Job", "CronJob"}
SKIP_KEY = "lint.cloud10x/skip"

findings, waived = [], []


def pod_spec(obj):
    kind, spec = obj["kind"], obj.get("spec") or {}
    if kind == "CronJob":
        spec = ((spec.get("jobTemplate") or {}).get("spec") or {})
    tpl = spec.get("template") or {}
    return tpl.get("metadata") or {}, tpl.get("spec") or {}, spec


def skips(obj, tpl_meta):
    out = set()
    for meta in (obj.get("metadata") or {}, tpl_meta):
        raw = (meta.get("annotations") or {}).get(SKIP_KEY, "")
        out |= {x.strip() for x in str(raw).split(",") if x.strip()}
    return out


def report(rule, obj, msg, skip=()):
    ident = "%s/%s" % (obj["kind"], (obj.get("metadata") or {}).get("name", "?"))
    (waived if rule in skip else findings).append((rule, ident, msg))


def sc(d):
    return (d or {}).get("securityContext") or {}


def every_container(pod, key, want):
    ctrs = (pod.get("containers") or []) + (pod.get("initContainers") or [])
    pod_ok = want(sc(pod))
    return pod_ok or all(want(sc(c)) for c in ctrs)


def check_workload(obj):
    meta_t, pod, spec = pod_spec(obj)
    kind = obj["kind"]
    skip = skips(obj, meta_t)
    r = lambda rule, msg: report(rule, obj, msg, skip)
    ctrs = (pod.get("containers") or []) + (pod.get("initContainers") or [])

    if not every_container(pod, "runAsNonRoot", lambda s: s.get("runAsNonRoot") is True):
        r("pod-non-root", "runAsNonRoot is not true")
    if not every_container(pod, "runAsUser", lambda s: isinstance(s.get("runAsUser"), int) and s["runAsUser"] != 0):
        r("pod-explicit-uid", "runAsUser missing or 0")
    if not every_container(pod, "seccomp", lambda s: (s.get("seccompProfile") or {}).get("type") in ("RuntimeDefault", "Localhost")):
        r("pod-seccomp", "seccompProfile not RuntimeDefault/Localhost")
    if pod.get("automountServiceAccountToken") is not False:
        r("pod-no-sa-token", "automountServiceAccountToken is not false")
    if pod.get("serviceAccountName") in (None, "", "default"):
        r("pod-sa-dedicated", "uses the default ServiceAccount")
    for k in ("hostNetwork", "hostPID", "hostIPC"):
        if pod.get(k):
            r("pod-no-host", "%s is true" % k)
    for v in pod.get("volumes") or []:
        if "hostPath" in v:
            r("pod-no-host", "hostPath volume %s" % v.get("name"))

    for c in ctrs:
        n, s = c.get("name", "?"), sc(c)
        if s.get("allowPrivilegeEscalation") is not False:
            r("ctr-no-priv-esc", "%s: allowPrivilegeEscalation is not false" % n)
        if s.get("privileged"):
            r("ctr-not-privileged", "%s: privileged" % n)
        if s.get("readOnlyRootFilesystem") is not True:
            r("ctr-readonly-root", "%s: readOnlyRootFilesystem is not true" % n)
        caps = s.get("capabilities") or {}
        if "ALL" not in (caps.get("drop") or []) or caps.get("add"):
            r("ctr-drop-all", "%s: must drop ALL and add nothing" % n)
        res = c.get("resources") or {}
        for part in ("requests", "limits"):
            for res_name in ("cpu", "memory"):
                if res_name not in (res.get(part) or {}):
                    r("ctr-resources", "%s: missing %s.%s" % (n, part, res_name))
        img = str(c.get("image", ""))
        last = img.rsplit("/", 1)[-1]
        if "@" not in img and (":" not in last or last.endswith(":latest")):
            r("ctr-image-tag", "%s: image '%s' has no pinned tag/digest" % (n, img))
        if kind in LONG and c in (pod.get("containers") or []):
            for p in ("readinessProbe", "livenessProbe"):
                if not c.get(p):
                    r("ctr-probes", "%s: missing %s" % (n, p))

    if "run" not in (meta_t.get("labels") or {}):
        r("wl-run-label", "pod template has no 'run' label")
    if kind == "StatefulSet" and not spec.get("volumeClaimTemplates"):
        r("sts-volume-claim", "no volumeClaimTemplates")


def selects(sel, labels):
    return bool(sel) and all((labels or {}).get(k) == v for k, v in sel.items())


def main(argv):
    if argv[:1] == ["--rules"]:
        for k, v in RULES.items():
            print("%-22s %s" % (k, v))
        return 0
    if len(argv) != 1 or not os.path.isdir(argv[0]):
        print(__doc__)
        return 2
    objs = []
    for f in sorted(glob.glob(os.path.join(argv[0], "*.yaml"))):
        try:
            with open(f) as fh:
                objs += [d for d in yaml.safe_load_all(fh) if isinstance(d, dict) and d.get("kind")]
        except yaml.YAMLError as e:
            print("FAIL   %-20s %s: %s" % ("yaml-parse", os.path.basename(f), str(e).splitlines()[0]))
            return 1
    if not objs:
        print("FAIL: no manifests in %s" % argv[0])
        return 1

    pdbs = [o for o in objs if o["kind"] == "PodDisruptionBudget"]
    ns_workloads, deny_ns = set(), set()
    for o in objs:
        ns = (o.get("metadata") or {}).get("namespace", "default")
        k = o["kind"]
        if k in WORKLOADS:
            ns_workloads.add(ns)
            check_workload(o)
            meta_t, _, spec = pod_spec(o)
            if k == "Deployment" and (spec.get("replicas") or 1) > 1:
                labels = meta_t.get("labels") or {}
                ok = any((p["metadata"].get("namespace", "default") == ns) and
                         selects(((p.get("spec") or {}).get("selector") or {}).get("matchLabels"), labels)
                         for p in pdbs)
                if not ok:
                    report("deploy-pdb", o, "replicas > 1 without a matching PodDisruptionBudget", skips(o, meta_t))
        elif k == "Namespace":
            lab = (o["metadata"].get("labels") or {})
            for m in ("enforce", "warn", "audit"):
                if "pod-security.kubernetes.io/" + m not in lab:
                    report("ns-pss", o, "missing label pod-security.kubernetes.io/" + m, skips(o, {}))
        elif k == "NetworkPolicy":
            sp = o.get("spec") or {}
            types = set(sp.get("policyTypes") or [])
            if not sp.get("podSelector") and {"Ingress", "Egress"} <= types and not sp.get("ingress") and not sp.get("egress"):
                deny_ns.add(ns)
        elif k == "Secret" and o.get("type") == "kubernetes.io/tls":
            if "tls.key" in (o.get("data") or {}) or "tls.key" in (o.get("stringData") or {}):
                report("secret-tls-key", o, "TLS private key committed", skips(o, {}))
    for ns in sorted(ns_workloads - deny_ns):
        findings.append(("netpol-default-deny", "Namespace/" + ns, "no default-deny NetworkPolicy (Ingress+Egress)"))

    for rule, ident, msg in waived:
        print("WAIVED %-20s %s: %s" % (rule, ident, msg))
    for rule, ident, msg in findings:
        print("FAIL   %-20s %s: %s" % (rule, ident, msg))
    print("lint: %d finding(s), %d waived, %d object(s)" % (len(findings), len(waived), len(objs)))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
