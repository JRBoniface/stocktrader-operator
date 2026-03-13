# External Secrets Operator — Installation & Configuration

Installs the [External Secrets Operator](https://external-secrets.io) (ESO) via Helm and configures it to read secrets from Azure Key Vault using [Workload Identity](https://azure.github.io/azure-workload-identity/docs/).

---

## Prerequisites

| Tool | Purpose |
|---|---|
| `helm` ≥ 3.12 | Install ESO chart |
| `kubectl` | Apply post-install manifests |
| `az` CLI | Configure Azure Workload Identity (if not using Terraform) |

The following must exist before installing ESO:

- An AKS cluster with **OIDC issuer enabled** and **Workload Identity enabled**
- A **User-Assigned Managed Identity (UAI)** with Key Vault Secrets read access
- An Azure **Key Vault** populated with the required secrets (see [Required Key Vault Secrets](#required-key-vault-secrets))

---

## Step 1 — Configure Azure Workload Identity

This step links the Kubernetes ServiceAccount that ESO runs under to the Azure UAI, enabling passwordless Key Vault access. If you provisioned infrastructure with Terraform (`module.external_secrets`), this step is already done — skip to [Step 2](#step-2--install-eso-via-helm).

### Get the AKS OIDC issuer URL

```bash
OIDC_ISSUER=$(az aks show \
  --name <AKS_CLUSTER_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query "oidcIssuerProfile.issuerUrl" \
  --output tsv)
echo $OIDC_ISSUER
```

### Get UAI details

```bash
UAI_CLIENT_ID=$(az identity show \
  --name <UAI_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query clientId --output tsv)

UAI_ID=$(az identity show \
  --name <UAI_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --query id --output tsv)
```

### Create the Federated Identity Credential

Links the Kubernetes ServiceAccount (`eso-wi` in `external-secrets`) to the UAI via OIDC:

```bash
az identity federated-credential create \
  --name eso-fic \
  --identity-name <UAI_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --issuer "$OIDC_ISSUER" \
  --subject "system:serviceaccount:external-secrets:eso-wi" \
  --audiences "api://AzureADTokenExchange"
```

---

## Step 2 — Install ESO via Helm

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --version 0.14.0 \
  -f helm-charts/external-secrets/values.yaml
```

Wait for ESO to be fully ready before proceeding:

```bash
kubectl wait --for=condition=available --timeout=120s \
  deployment/external-secrets \
  deployment/external-secrets-webhook \
  deployment/external-secrets-cert-controller \
  -n external-secrets
```

---

## Step 3 — Apply Post-Install Manifests

These manifests contain environment-specific values (tenant ID, Key Vault URI, UAI client ID) and are **not committed to git**. Create and apply them locally after the Helm install.

### ServiceAccount

Creates the Kubernetes ServiceAccount annotated with the UAI client ID. ESO exchanges this SA's token for an Azure AD token to access Key Vault.

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: eso-wi
  namespace: external-secrets
  labels:
    azure.workload.identity/use: "true"
  annotations:
    azure.workload.identity/client-id: <UAI_CLIENT_ID>
EOF
```

Replace `<UAI_CLIENT_ID>` with the value from:
```bash
az identity show --name <UAI_NAME> --resource-group <RESOURCE_GROUP> --query clientId --output tsv
# or from Terraform: terraform output -raw external_secrets_service_account
# (then get client ID from: terraform output -raw uai_client_id)
```

### ClusterSecretStore

Points ESO at your Azure Key Vault. Create and apply this manifest:

```bash
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: azure-kv
spec:
  provider:
    azurekv:
      tenantId: "<TENANT_ID>"
      vaultUrl: "<KEY_VAULT_URI>"
      authType: WorkloadIdentity
      serviceAccountRef:
        name: eso-wi
        namespace: external-secrets
EOF
```

| Placeholder | How to get the value |
|---|---|
| `<TENANT_ID>` | `az account show --query tenantId --output tsv` or `terraform output -raw tenant_id` |
| `<KEY_VAULT_URI>` | `az keyvault show --name <KV_NAME> --query properties.vaultUri --output tsv` or `terraform output -raw key_vault_uri` |

Verify the store is ready:
```bash
kubectl get clustersecretstore azure-kv
# STATUS column should show: Valid
```

---

## Step 4 — Create ExternalSecrets

### Stock Trader Application Credentials

Syncs all Stock Trader application secrets from Key Vault into the `stock-trader` namespace:

```bash
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ClusterExternalSecret
metadata:
  name: stock-trader-secret-credentials
spec:
  namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: stock-trader
  externalSecretSpec:
    refreshInterval: 1h
    secretStoreRef:
      name: azure-kv
      kind: ClusterSecretStore
    target:
      name: stock-trader-secret-credentials
      creationPolicy: Owner
    data:
      - secretKey: cloudant.id
        remoteRef:
          key: cloudant-id
      - secretKey: cloudant.password
        remoteRef:
          key: cloudant-password
      - secretKey: database.id
        remoteRef:
          key: database-id
      - secretKey: database.password
        remoteRef:
          key: database-password
      - secretKey: database.host
        remoteRef:
          key: database-host
      - secretKey: redis.url
        remoteRef:
          key: redis-url
      - secretKey: oidc.clientId
        remoteRef:
          key: oidc-clientId
      - secretKey: oidc.clientSecret
        remoteRef:
          key: oidc-clientSecret
EOF
```

### CouchDB Credentials

Syncs CouchDB admin credentials from Key Vault into the `couchdb` namespace. Required before deploying CouchDB (see [helm-charts/couchdb/](../couchdb/)):

```bash
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: couchdb-credentials
  namespace: couchdb
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: azure-kv
    kind: ClusterSecretStore
  target:
    name: couchdb-credentials
    creationPolicy: Owner
  data:
    - secretKey: adminUsername
      remoteRef:
        key: couchdb-admin-username
    - secretKey: adminPassword
      remoteRef:
        key: couchdb-admin-password
    - secretKey: cookieAuthSecret
      remoteRef:
        key: couchdb-cookie-auth-secret
EOF
```

---

## Required Key Vault Secrets

The following secrets must exist in Azure Key Vault before any ExternalSecrets can sync:

| Key Vault Secret Name | Used By | Description |
|---|---|---|
| `cloudant-id` | Stock Trader | Cloudant service username / API key |
| `cloudant-password` | Stock Trader | Cloudant service password |
| `database-id` | Stock Trader | PostgreSQL username |
| `database-password` | Stock Trader | PostgreSQL password |
| `database-host` | Stock Trader | PostgreSQL FQDN |
| `redis-url` | Stock Trader | Redis connection string |
| `oidc-clientId` | Stock Trader | OIDC client ID |
| `oidc-clientSecret` | Stock Trader | OIDC client secret |
| `couchdb-admin-username` | CouchDB | CouchDB admin username (e.g. `admin`) |
| `couchdb-admin-password` | CouchDB | CouchDB admin password (strong random string) |
| `couchdb-cookie-auth-secret` | CouchDB | Erlang cookie / CouchDB cookie auth secret |

If infrastructure was provisioned via Terraform, the database, Redis, and OIDC secrets are populated automatically. CouchDB secrets must be set manually:

```bash
az keyvault secret set --vault-name <KV_NAME> --name couchdb-admin-username --value "admin"
az keyvault secret set --vault-name <KV_NAME> --name couchdb-admin-password --value "<STRONG_RANDOM_PASSWORD>"
az keyvault secret set --vault-name <KV_NAME> --name couchdb-cookie-auth-secret --value "<STRONG_RANDOM_STRING>"
```

---

## Verify

```bash
# ESO operator pods
kubectl get pods -n external-secrets

# ClusterSecretStore status (should be Valid)
kubectl get clustersecretstore azure-kv

# ExternalSecret sync status
kubectl get externalsecret -n couchdb
kubectl get clusterexternalsecret stock-trader-secret-credentials
```
