# IBM Stock Trader Operator

A Kubernetes Operator that installs and configures the [IBM Stock Trader](https://github.com/IBMStockTrader) sample application. It is built with [Operator SDK](https://sdk.operatorframework.io/) (v1.40.0) using the Helm plugin, wrapping the umbrella Helm chart in `operator/helm-charts/stocktrader/`.

The operator manages the full lifecycle of the Stock Trader microservices. It does not provision cloud infrastructure or install prerequisite operators — those concerns are handled separately (see [Prerequisites](#prerequisites) below).

Originally created for IBM Cloud, the operator has been tested across AWS, Azure, and GCP.

![Architectural Diagram](images/stock-trader.png)

---

## Table of Contents

- [IBM Stock Trader Operator](#ibm-stock-trader-operator)
  - [Table of Contents](#table-of-contents)
  - [Repository Structure](#repository-structure)
  - [Documentation](#documentation)
  - [Prerequisites](#prerequisites)
  - [Installing the Stocktrader Operator](#installing-the-stocktrader-operator)
  - [Deploying a Stock Trader Instance](#deploying-a-stock-trader-instance)
  - [Accessing the Application](#accessing-the-application)
  - [Development](#development)

---

## Repository Structure

```
stocktrader-operator/               # Root repository
    operator/           # Operator core
        helm-charts/
            stocktrader/            # Umbrella Helm chart for the Stock Trader application
            external-secrets/       # ESO Helm values + post-install instructions
            couchdb/                # CouchDB Helm values + install instructions
        config/                     # Operator SDK Kustomize config (CRD, RBAC, manager)
        bundle/                     # OLM bundle manifests
        catalog/                    # OLM catalog
        catalog-source.yaml         # CatalogSource to register this operator with OLM
        subscription.yaml           # Subscription to install this operator via OLM
        watches.yaml                # Maps StockTrader CR to the Helm chart
        Makefile                    # Build, bundle, and catalog targets
    platform-operators/             # ArgoCD bootstrap manifests (applied once, manually)
        argocd/                     # ArgoCD Operator (OLM) + ArgoCD instance
        README.md                   # Full bootstrap sequence
    gitops/                         # ArgoCD App of Apps (GitOps)
        app-of-apps.yaml            # Root Application
        applications/               # Individual Application manifests
    docs/                           # Detailed documentation
    Makefile                        # Thin wrapper — delegates all targets to operator/
```

---

## Documentation

| Document | Description |
|---|---|
| [docs/architecture.md](docs/architecture.md) | System architecture, component diagram, secret flow, and GitOps ordering |
| [docs/getting-started.md](docs/getting-started.md) | End-to-end guide from infrastructure provisioning to a running application |
| [docs/configuration.md](docs/configuration.md) | Full `StockTrader` CR field reference, organised by section |
| [docs/development.md](docs/development.md) | Build workflow, make targets, OLM bundle and catalog process |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Diagnostic commands and fixes for common problems |

---

## Prerequisites

The following must be in place before deploying the operator:

**1. Cloud infrastructure**
Provision the required cloud resources (AKS/EKS/GKE, PostgreSQL, Redis, Key Vault, networking) using the [stocktrader-setup](https://github.com/IBMStockTrader/stocktrader-setup) repository.

**2. OLM installed on the cluster**
```bash
curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/latest/download/install.sh | bash -s <version>
```
For further details see the [OLM getting started guide](https://olm.operatorframework.io/docs/getting-started/).

**3. External Secrets Operator installed**
ESO syncs secrets from Azure Key Vault to Kubernetes. See [operator/helm-charts/external-secrets/README.md](operator/helm-charts/external-secrets/README.md) for the full install guide including Workload Identity setup and post-install manifests.

**4. CouchDB installed**
See [operator/helm-charts/couchdb/README.md](operator/helm-charts/couchdb/README.md).

**5. ArgoCD bootstrapped** (GitOps path only)
See [platform-operators/README.md](platform-operators/README.md) for the full bootstrap sequence.

---

## Installing the Stocktrader Operator

The operator is distributed via an OLM catalog hosted on GHCR. Apply the `CatalogSource` and `Subscription` from the repo root:

```bash
kubectl apply -f operator/catalog-source.yaml
kubectl apply -f operator/subscription.yaml
```

Wait for the operator to be ready:
```bash
kubectl get csv -w
```

The CSV should reach `Succeeded` phase before proceeding.

---

## Deploying a Stock Trader Instance

Once the operator is running, create a `StockTrader` CR to deploy the application. An annotated example is provided at [`operator/config/samples/operators_v1_stocktrader.yaml`](operator/config/samples/operators_v1_stocktrader.yaml).

Edit the sample to match your environment (database host, Redis URL, OIDC configuration, etc.), then apply:

```bash
kubectl apply -f operator/config/samples/operators_v1_stocktrader.yaml
```

---

## Accessing the Application

The operator provisions a load balancer service for the Trader frontend. Retrieve the external IP:

```bash
kubectl get svc | grep trader-service
```

Access the application in a browser:
```
https://<trader-service-ip>:9443/trader
```

![Login](images/Login.png)

---

## Development

The Makefile provides all standard build targets. Run `make help` for the full list.

**Build and push the operator image:**
```bash
make docker-build docker-push IMG=ghcr.io/ibmstocktrader/stocktrader-operator:v1.0.0
```

**Regenerate and validate the OLM bundle:**
```bash
make bundle
```

**Build and push the bundle image:**
```bash
make bundle-build bundle-push
```

**Build and push the catalog image:**
```bash
make catalog-build catalog-push
```

Built images are published to GHCR at [`ghcr.io/ibmstocktrader/stocktrader-operator`](https://github.com/IBMStockTrader/stocktrader-operator/pkgs/container/stocktrader-operator).
