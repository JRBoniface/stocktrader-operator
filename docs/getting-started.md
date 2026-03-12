# Getting Started

End-to-end guide for deploying the Stock Trader application from scratch. Follow the steps in order — earlier steps create resources that later steps depend on.

## Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| `terraform` ≥ 1.5 | Provision cloud infrastructure | [terraform.io](https://developer.hashicorp.com/terraform/install) |
| `kubectl` | Interact with the cluster | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| `helm` ≥ 3.12 | Used by the operator SDK tooling | [helm.sh](https://helm.sh/docs/intro/install/) |
| `kustomize` ≥ 5.0 | Apply Kustomize manifests | [kubectl.docs.kubernetes.io](https://kubectl.docs.kubernetes.io/installation/kustomize/) |
| `make` | Drive build targets | System package manager |
| A container registry | Store operator images | GHCR, ACR, ECR, GCR, etc. |

---

## Step 1 — Provision cloud infrastructure

Run Terraform in the [stocktrader-setup](https://github.com/IBMStockTrader/stocktrader-setup) repository to create the AKS cluster, Azure Database for PostgreSQL, Azure Cache for Redis, Azure Key Vault, and all supporting networking:

```bash
cd <stocktrader-setup>/azure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your subscription ID, location, etc.
terraform init
terraform apply
```

Terraform will:
- Create a managed AKS cluster with OIDC issuer enabled
- Create a User-Assigned Identity (UAI) with Key Vault access
- Create a Kubernetes `ServiceAccount` and Azure `FederatedIdentityCredential` for ESO
- Populate Azure Key Vault with the database and Redis connection secrets
- Output the values needed for `config.env` in the next step

---

## Step 2 — Populate config.env

ESO uses a `config.env` file to know which tenant, Key Vault, and service account to use. This file is gitignored — generate it from Terraform outputs:

```bash
cd <stocktrader-setup>/azure

cat > <this-repo>/platform-operators/external-secrets/overlays/config.env << EOF
TENANT_ID=$(terraform output -raw tenant_id)
KEY_VAULT_URI=$(terraform output -raw key_vault_uri)
SERVICE_ACCOUNT_NAME=$(terraform output -raw external_secrets_service_account)
ESO_NAMESPACE=$(terraform output -raw external_secrets_namespace)
CREDENTIALS_SECRET_NAME=$(terraform output -raw credentials_secret_name)
STOCK_TRADER_NAMESPACE=$(terraform output -raw stock_trader_namespace)
EOF
```

See [`platform-operators/external-secrets/overlays/config.env.example`](../platform-operators/external-secrets/overlays/config.env.example) for all required keys and descriptions.

---

## Step 3 — Connect to the cluster

```bash
az aks get-credentials --resource-group <your-rg> --name <your-aks-cluster>
kubectl get nodes   # verify connectivity
```

---

## Step 4 — Install OLM

The CouchDB and ArgoCD operators are installed via OLM. Install OLM on the cluster if not already present:

```bash
curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/latest/download/install.sh | bash -s <version>
# e.g. bash -s v0.27.0

kubectl get pods -n olm   # verify
```

---

## Step 5 — Bootstrap ArgoCD

ArgoCD must be installed before it can manage the remaining operators. Apply the ArgoCD operator Kustomize overlay, then wait for the instance:

```bash
kubectl apply -k platform-operators/argocd/overlays/azure
```

Wait for the OLM CSV to reach `Succeeded`. This is the correct signal — it confirms the operator pod **and its conversion webhook** are fully running. Waiting only for the CRD to be established is not sufficient:

```bash
kubectl get csv -n argocd -w
# Continue when STATUS = Succeeded
```

Now create the ArgoCD instance. This must be a separate apply — the `ArgoCD` CRD's conversion webhook must be running before the instance CR is submitted:

```bash
kubectl apply -f platform-operators/argocd/base/argocd-instance.yaml
```

Wait for ArgoCD to be fully ready (2–5 minutes):

```bash
kubectl wait --for=condition=Ready argocd/argocd -n argocd --timeout=300s
```

Verify the ArgoCD pods are running:

```bash
kubectl get pods -n argocd
```

---

## Step 6 — Connect your Git repository to ArgoCD

Before applying the App of Apps, configure ArgoCD to access this repository (if it is private):

```bash
# Via CLI
argocd repo add https://github.com/<your-org>/stocktrader-operator \
  --username <user> \
  --password <token>

# Or via kubectl secret
kubectl create secret generic stocktrader-repo \
  --from-literal=type=git \
  --from-literal=url=https://github.com/<your-org>/stocktrader-operator \
  --from-literal=password=<token> \
  --from-literal=username=<user> \
  -n argocd \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret stocktrader-repo argocd.argoproj.io/secret-type=repository -n argocd
```

Update the `repoURL` in [`gitops/app-of-apps.yaml`](../gitops/app-of-apps.yaml) to point to your fork.

---

## Step 7 — Apply the App of Apps

Hand control to ArgoCD. This single command triggers all four sync waves:

```bash
kubectl apply -f gitops/app-of-apps.yaml
```

ArgoCD will now incrementally deploy:

| Wave | What happens |
|---|---|
| 0 | CouchDB Operator installed via OLM |
| 1 | ESO installed via Helm; ClusterSecretStore created; Key Vault secrets synced to cluster |
| 2 | StockTrader Operator CRD, RBAC, and manager pod deployed |
| 3 | StockTrader CR applied — operator reconciles and deploys all application services |

Monitor progress in the ArgoCD UI or via:

```bash
kubectl get applications -n argocd
```

> **Note:** Wave 1 may report a transient error on first sync. The ESO Helm chart installs the `ClusterSecretStore` CRD and then immediately attempts to create a `ClusterSecretStore` object in the same sync. ArgoCD's retry policy (5 retries, 30s backoff) will resolve this automatically once the CRD is established. This is expected behaviour.

---

## Step 8 — Configure the StockTrader CR

The sample CR at [`stocktrader-operator/config/samples/operators_v1_stocktrader.yaml`](../stocktrader-operator/config/samples/operators_v1_stocktrader.yaml) contains default placeholder values. Before wave 3 successfully reconciles, edit it to match your environment:

Key fields to set:

```yaml
spec:
  global:
    auth: oidc          # or 'basic' for development
    externalSecret: true
    secretName: '<your-credentials-secret-name>'  # must match CREDENTIALS_SECRET_NAME in config.env
  redis:
    urlWithCredentials: redis://<user>:<pass>@<host>:6379
  database:
    host: <postgres-host>
    db: trader
    id: <db-user>
    password: <db-password>
  oidc:
    discoveryUrl: <your-oidc-discovery-url>
    clientId: <your-client-id>
    clientSecret: <your-client-secret>
  stockQuote:
    iexApiKey: <your-IEX-API-key>
```

See [configuration.md](configuration.md) for the full CR reference.

---

## Step 9 — Verify the deployment

```bash
# Operator running
kubectl get pods -n stocktrader-operator-system

# Application pods
kubectl get pods -n stock-trader

# StockTrader CR status
kubectl get stocktrader -n stock-trader

# Credentials secret synced from Key Vault
kubectl get externalsecret -n stock-trader
kubectl get secret <credentials-secret-name> -n stock-trader
```

---

## Manual installation (without ArgoCD)

If you prefer applying manifests directly without GitOps:

```bash
# Step 1 — Install platform operators (two phases — see platform-operators/README.md)
kubectl apply -k platform-operators --enable-helm
kubectl wait --for=condition=established --timeout=120s crd/clustersecretstores.external-secrets.io
kubectl wait --for=condition=established --timeout=120s crd/couchdbclusters.couchdb.apache.org
kubectl apply -k platform-operators --enable-helm

# Step 2 — Deploy the stocktrader operator
kubectl apply -k stocktrader-operator/config/default

# Step 3 — Apply the StockTrader instance
kubectl apply -f stocktrader-operator/config/samples/operators_v1_stocktrader.yaml
```

---

## Accessing the application

The default service for the UI is accessible via port-forward for local testing:

```bash
kubectl port-forward svc/<release-name>-trader-service 9080:9080 -n stock-trader
```

Then open `http://localhost:9080/trader` in your browser.

For production access, configure `global.ingress: true` in the CR and ensure an ingress controller is installed on the cluster (e.g. the AGIC add-on for AKS).
