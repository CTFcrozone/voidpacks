# Auditing a project

An audit is a read-only review of a project against this pack. It reports findings; it changes no file.

## What to review

1. `kdd.yaml` against `kdd.md`: schema, realms, `confirm_delete`, registries, context uniqueness, versions.
2. Manifests against `kubernetes.md`, `lint.md` and `database.md`: security context, probes, resources, ServiceAccounts, NetworkPolicy (both sides, pod ports, DNS), PDBs, Pod Security labels, secrets handling, StatefulSet storage.
3. Dockerfiles against `containers.md` and `parameters.md`: floating or pinned toolchain, base image policy, non-root numeric user, exec-form entrypoint, `--locked`, `.dockerignore`.
4. Cross-file consistency against `contract.md`: names, ports, env vars, image tags, labels, registry and cluster names between `kdd.yaml`, scripts and manifests.
5. Code against the contract: every env var read is set in the manifests; health and readiness endpoints exist and match the probes.
6. Operations: how database upgrades, backups and rollbacks are handled (`database.md`), and who applies to production (`environments.md`).

## Already enforced mechanically

`check.sh` and `lint.py` enforce hardening fields, probes, resources, run labels, image tags and digests, env vars, version, registry, listed overlay files, and the realm rules (`environments.md`, "Adding a realm"). An audit assumes they passed unless the files plainly contradict it and spends its effort on what they cannot see: design, operations, data safety, missing policies, wrong-but-valid values.

## Rules

- **Evidence or silence.** Every finding quotes, verbatim, the project lines it is about and the pack sentence that defines the rule. If either quote is missing, drop the finding.
- **Project quotes come from the project.** The `Project:` quote is from the project's own files, never from the pack's samples or guides. The samples use other names (`k3d-rust10x`, `dev_k3s`, ...); a value found only there is not the project's.
- **Refute before reporting.** For each candidate, look in the other files for what would make it wrong and quote what was checked: a NetworkPolicy with an empty `podSelector` selects every pod; a later `kdd kapply` stage in `k3d.sh` applies files not listed in an earlier one; a variable set in a ConfigMap rather than `env:`; a Service port versus the pod port. If the refutation holds, or the "Checked and not refuted" line shows the rule is satisfied, the finding is dropped.
- **A file not given is not a missing file.** Report a file as absent only when the listing shows its directory and it is not there; otherwise list it under "Not checked".
- **Only what the files show.** Do not invent issues. Fewer verified findings beat a long list. "No findings" is a valid result.
- **Unverifiable statically** (cluster behavior, secret values, image contents) goes under "Not checked".
- **No line numbers.** Give the file and the quoted text.
- **Final report only.** No reasoning or second thoughts in the output; check silently, then write only what survived.

## Output

Findings ordered by impact, most impactful first, in exactly this shape:

```
## Findings
1. <file> - <what is wrong>
   Project: "<verbatim quote>"
   Rule: "<verbatim pack sentence>" (<pack file, section>)
   Checked and not refuted: <what was looked for in other files>
   Fix: <the concrete change>

## Not checked
- <item and why>

## Verified OK
- <short list of areas that match the pack>
```
