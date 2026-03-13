# GitOps — ArgoCD Bootstrap

This directory contains an ArgoCD [App of Apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) configuration that deploys the full Stock Trader stack using sync waves to enforce ordering.

This is an **alternative to the manual Kustomize approach** documented in [platform-operators/README.md](../platform-operators/README.md). The existing `platform-operators/`, `operator/config/`, and `operator/helm-charts/` directories are unchanged — this directory only adds the ArgoCD Application manifests that point to them.

---

## Deployment Order

| Wave | Application | Path | Waits for |
|---|---|---|---|
| 0 | `couchdb-operator` | `platform-operators/couchdb/overlays/azure` | — |
| 1 | `external-secrets-operator` | `platform-operators/external-secrets/overlays` | Wave 0 Healthy |
| 2 | `stocktrader-operator` | `operator/config/default` | Wave 1 Healthy |
| 3 | `stocktrader-instance` | `operator/config/samples` | Wave 2 Healthy |

ArgoCD waits for each wave to reach `Healthy` before applying the next.

---

## Prerequisites

**1. ArgoCD installed via its operator**
```bash
kubectl apply -k platform-operators/argocd/overlays/azure
kubectl wait --for=condition=Ready argocd/argocd -n argocd --timeout=300s
```
See [platform-operators/argocd/](../platform-operators/argocd/) for details. The ArgoCD instance is configured with `kustomizeBuildOptions: "--enable-helm"` automatically — no manual `argocd-cm` edit required.

**2. OLM installed**
```bash
operator-sdk olm install
```

**3. Terraform applied** in the infrastructure repository — ServiceAccount and FederatedIdentityCredential for ESO must exist.

**4. `config.env` values available to ArgoCD** (see [Config.env and ArgoCD](#configenv-and-argocd) below).

---

## Usage

Update the `repoURL` in `app-of-apps.yaml` and each `applications/*.yaml` to match your fork, then apply the root Application:

```bash
kubectl apply -f gitops/app-of-apps.yaml
```

ArgoCD will discover and apply the child Applications in wave order. Monitor progress:
```bash
argocd app list
argocd app get stocktrader-bootstrap
```

---

## Config.env and ArgoCD

`platform-operators/external-secrets/overlays/config.env` is gitignored — it contains Terraform output values and must not be committed. This creates a challenge for ArgoCD which syncs from Git.

The recommended approaches are:

**Option A — Kubernetes Secret + ConfigManagementPlugin**
Store the Terraform outputs as a Kubernetes Secret post `terraform apply`, then configure a ArgoCD ConfigManagementPlugin that generates `config.env` from the secret at sync time.

**Option B — ArgoCD Vault Plugin**
Use [argocd-vault-plugin](https://argocd-vault-plugin.readthedocs.io/) to inject values from Azure Key Vault directly into the manifests, replacing the `config.env` mechanism entirely.

**Option C — Commit config.env to a private repo**
If the infrastructure repo is private and access-controlled, `config.env` can be committed there and ArgoCD configured with a multi-source Application referencing both repos.

---

## Known Limitations

**ESO CRD ordering**
The `ClusterSecretStore` CRD is installed by the ESO Helm chart in wave 1. The first sync will report a partial error for the `ClusterSecretStore` object as the CRD does not yet exist. The `retry` policy on `external-secrets-operator.yaml` (5 retries, 30s backoff) resolves this automatically on the second attempt. This is expected on first install only.

**OLM vs. direct install for stocktrader-operator**
Wave 2 deploys the stocktrader operator via `operator/config/default` directly, bypassing OLM. If OLM-managed installation is preferred, replace the `path` in `gitops/applications/stocktrader-operator.yaml` with a path pointing to a `CatalogSource` + `Subscription` manifest. The `operator/catalog-source.yaml` and `operator/subscription.yaml` can be used as a reference.
