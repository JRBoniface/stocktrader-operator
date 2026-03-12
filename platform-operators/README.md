# Operators

This directory contains Kustomize manifests for installing the prerequisite operators required by the Stock Trader application. These operators must be installed on the cluster **before** the stocktrader operator is deployed.

## Overview

The Stock Trader application depends on two third-party operators:

| Operator | Purpose | Install method |
|---|---|---|
| **CouchDB Operator** | Manages CouchDB database instances | OLM Subscription |
| **External Secrets Operator (ESO)** | Syncs secrets from Azure Key Vault to Kubernetes | Helm (via Kustomize) |

These operators are entirely separate from the stocktrader operator itself. This directory only contains the manifests to *install* them — not their configuration or the application resources they manage.

## Relationship to Terraform

ESO requires two Azure-side resources that are created by Terraform (in the infrastructure repository) before these manifests can be applied:

- A Kubernetes **ServiceAccount** annotated with the User-Assigned Identity (UAI) client ID
- An Azure **Federated Identity Credential** linking the ServiceAccount to the UAI via OIDC

Terraform outputs the values needed here (tenant ID, Key Vault URI, namespace, service account name) which are written to `platform-operators/external-secrets/overlays/config.env`. Kustomize reads that file and injects the values into the manifests via `replacements`. The two repositories remain fully decoupled — Terraform writes `config.env`, Kustomize reads it.

## Directory Structure

```
platform-operators/
    kustomization.yaml                  # Managed by ArgoCD after bootstrap — references couchdb + ESO overlays
    argocd/                             # BOOTSTRAP ONLY — apply manually before using gitops/
        base/
            kustomization.yaml
            namespace.yaml
            catalog-source.yaml         # OperatorHub community catalog
            operator-group.yaml
            subscription.yaml
            argocd-instance.yaml        # ArgoCD CR with --enable-helm configured
        overlays/
            azure/
                kustomization.yaml
    couchdb/
        base/
            kustomization.yaml          # Resources: namespace, catalog-source, operator-group, subscription
            namespace.yaml              # Creates the couchdb namespace
            catalog-source.yaml         # Registers CouchDB catalog with OLM
            operator-group.yaml         # Scopes operator to couchdb namespace
            subscription.yaml           # Instructs OLM to install the CouchDB operator
        overlays/
            azure/
                kustomization.yaml      # AKS overlay — inherits base unchanged
    external-secrets/
        base/
            kustomization.yaml          # helmCharts (ESO) + ClusterSecretStore resource
            helm-values.yaml            # Static, environment-agnostic Helm values
            cluster-secret-store.yaml   # ClusterSecretStore with empty fields (filled by overlay)
        overlays/
            kustomization.yaml          # ConfigMapGenerator + replacements from config.env
            external-secret.yaml        # Syncs 8 keys from Key Vault into the app namespace
            config.env.example          # Template — copy to config.env and populate
            .gitignore                  # Excludes config.env from git
```

## Bootstrap Order

ArgoCD must exist before it can manage the other operators. The full bootstrap sequence is:

```bash
# Step 1 — Install the ArgoCD operator via OLM
kubectl apply -k platform-operators/argocd/overlays/azure

# Wait for the CSV to reach Succeeded — this confirms the operator pod and its
# conversion webhook are fully ready (CRD established alone is not sufficient)
kubectl get csv -n argocd -w
# When the STATUS column shows Succeeded, continue:

# Step 2 — Create the ArgoCD instance
kubectl apply -f platform-operators/argocd/base/argocd-instance.yaml
kubectl wait --for=condition=Ready argocd/argocd -n argocd --timeout=300s

# Step 3 — Hand control to ArgoCD (applies couchdb, ESO, stocktrader operator, instance)
kubectl get secrets -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
```

After step 2, ArgoCD manages everything — `platform-operators/kustomization.yaml` is applied by ArgoCD, not manually.

---

## Prerequisites

Before applying these manifests:

1. **OLM installed** on the cluster. Verify with:
   ```bash
   kubectl get pods -n olm
   ```

2. **Terraform applied** in the infrastructure repository:
   ```bash
   cd <terraform-repo>/azure
   terraform apply
   ```
   This creates the ServiceAccount and FederatedIdentityCredential required by ESO.

3. **`config.env` populated** from Terraform outputs:
   ```bash
   cd <terraform-repo>/azure
   cd <operator-repo>/platform-operators/external-secrets/overlays/config.env << EOF
   TENANT_ID=$(terraform output -raw tenant_id)
   KEY_VAULT_URI=$(terraform output -raw key_vault_uri)
   SERVICE_ACCOUNT_NAME=$(terraform output -raw external_secrets_service_account)
   ESO_NAMESPACE=$(terraform output -raw external_secrets_namespace)
   CREDENTIALS_SECRET_NAME=$(terraform output -raw credentials_secret_name)
   STOCK_TRADER_NAMESPACE=$(terraform output -raw stock_trader_namespace)
   EOF
   ```
   See [external-secrets/overlays/config.env.example](external-secrets/overlays/config.env.example) for all required keys. `config.env` is gitignored — never commit it.

## Installation

Apply is split into two phases due to a CRD ordering constraint: the `ClusterSecretStore` CRD is created by the ESO Helm chart, so it must be established before the `ClusterSecretStore` object can be applied in the same kustomization.

### Phase 1 — Install operators and register CRDs

```bash
kubectl apply -k platform-operators --enable-helm
```

### Wait for CRDs to be established

```bash
kubectl wait --for=condition=established --timeout=120s \
  crd/clustersecretstores.external-secrets.io

kubectl wait --for=condition=established --timeout=120s \
  crd/couchdbclusters.couchdb.apache.org
```

### Phase 2 — Apply ClusterSecretStore

The second apply is idempotent for everything except the `ClusterSecretStore`, which can now be created successfully:

```bash
kubectl apply -k platform-operators --enable-helm
```

### Verify

```bash
# CouchDB operator running
kubectl get pods -n couchdb

# ESO pods running
kubectl get pods -n external-secrets

# ClusterSecretStore ready
kubectl get clustersecretstore azure-kv

# ExternalSecret synced
kubectl get externalsecret -n <stock-trader-namespace>
```

## Adding a New Cloud Provider

The base manifests are cloud-agnostic. To add support for a different cloud (e.g. GCP, AWS):

1. Create `overlays/<provider>/` directories under both `couchdb/` and `external-secrets/`
2. For CouchDB — create a `kustomization.yaml` pointing to `../../base`, adding any patches needed (e.g. different OLM namespace for OpenShift)
3. For ESO — create a `kustomization.yaml`, `external-secret.yaml`, and `config.env.example` with provider-specific replacement keys
4. Add the new overlays as additional resources in `platform-operators/kustomization.yaml`

CouchDB's Azure overlay requires no patches — the OLM defaults (`olm` namespace) are correct for AKS. The overlay exists as an explicit entry point and to document how an OpenShift overlay would differ.
