# Architecture

## Overview

The Stock Trader application is a microservices sample demonstrating cloud-native patterns on Kubernetes. This repository provides the Kubernetes Operator that installs, configures, and manages the entire application lifecycle using a single custom resource.

## Component Map

```
┌────────────────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                                  │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ platform-operators/                                                  │  │
│  │                                                                      │  │
│  │  ┌──────────────────┐   ┌───────────────────────────────────────┐   │  │
│  │  │  ArgoCD Operator │   │  External Secrets Operator (ESO)      │   │  │
│  │  │  ns: argocd      │   │  ns: external-secrets                 │   │  │
│  │  │                  │   │                                       │   │  │
│  │  │  Manages GitOps  │   │  ClusterSecretStore ──► Azure Key Vault│  │  │
│  │  │  sync waves      │   │  ExternalSecret ──► stock-trader-creds │  │  │
│  │  └──────────────────┘   └───────────────────────────────────────┘   │  │
│  │                                                                      │  │
│  │  ┌──────────────────┐                                                │  │
│  │  │  CouchDB Operator│                                                │  │
│  │  │  ns: couchdb     │                                                │  │
│  │  │                  │                                                │  │
│  │  │  Manages CouchDB │                                                │  │
│  │  │  cluster CRs     │                                                │  │
│  │  └──────────────────┘                                                │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                            │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ operator/                                                │  │
│  │                                                                      │  │
│  │  ┌──────────────────────────────────┐                                │  │
│  │  │  StockTrader Operator            │                                │  │
│  │  │  ns: stocktrader-operator-system │                                │  │
│  │  │                                  │                                │  │
│  │  │  Watches: StockTrader CR ────────┼──► Helm chart reconciliation  │  │
│  │  └──────────────────────────────────┘                                │  │
│  │                                                                      │  │
│  │  ┌──────────────────────────────────────────────────────────────┐   │  │
│  │  │ Stock Trader Application (ns: stock-trader)                  │   │  │
│  │  │                                                              │   │  │
│  │  │  broker ─► portfolio ─► stock-quote                         │   │  │
│  │  │     │           │                                           │   │  │
│  │  │     ▼           ▼                                           │   │  │
│  │  │  trader/tradr  trade-history                                │   │  │
│  │  │     │                                                       │   │  │
│  │  │     ▼                                                       │   │  │
│  │  │  messaging ─► notification-slack / notification-twitter     │   │  │
│  │  └──────────────────────────────────────────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘

External dependencies:
  Azure Key Vault ◄─── ESO ClusterSecretStore (Workload Identity / OIDC)
  Azure Database for PostgreSQL ◄───────── portfolio / trade-history services
  Azure Cache for Redis ◄──────────────── stock-quote service (quote caching)
  IEX Cloud API ◄──────────────────────── stock-quote service
```

## Repositories

This application spans two repositories:

| Repository | Purpose |
|---|---|
| [stocktrader-setup](https://github.com/IBMStockTrader/stocktrader-setup) | Terraform — provisions cloud infrastructure (AKS, PostgreSQL, Redis, Key Vault, networking) |
| [stocktrader-operator](https://github.com/IBMStockTrader/stocktrader-operator) _(this repo)_ | Kubernetes Operator — installs and manages the application and its prerequisite operators |

The two repositories are deliberately decoupled. Terraform writes connection strings and credentials to Azure Key Vault; the ESO synchronises them into a Kubernetes `Secret` in the application namespace. The operator never interacts with Terraform state directly.

## Operator Design

The stocktrader operator is a **Helm-based operator** built with Operator SDK. It:

1. Watches for `StockTrader` custom resources in any namespace
2. Reconciles the cluster state against the `helm-charts/stocktrader/` umbrella chart
3. Passes all CR `spec` fields directly to the Helm chart as values
4. Handles upgrades, rollbacks, and deletion via standard Operator SDK Helm reconciliation

The operator does **not** manage the platform operators (CouchDB, ESO, ArgoCD). Those are installed separately via the `platform-operators/` Kustomize manifests and are treated as infrastructure-level dependencies.

## Secret Flow

```
Terraform apply
    │
    ▼
Azure Key Vault
    │  (8 secrets: db host, db password, redis URL, etc.)
    │
    ▼
ESO ClusterSecretStore
    │  (authenticates via Workload Identity — OIDC FIC + UAI)
    │
    ▼
ExternalSecret (ns: stock-trader)
    │  (syncs all 8 keys into one Kubernetes Secret)
    │
    ▼
stock-trader-credentials Secret
    │
    ├──► portfolio service (db credentials)
    ├──► trade-history service (db credentials)
    └──► stock-quote service (redis URL)
```

The Workload Identity chain is established entirely by Terraform (`module.external_secrets` in `stocktrader-setup`). The operator repo consumes the outputs via `platform-operators/external-secrets/overlays/config.env`.

## GitOps Deployment Order

When deploying via ArgoCD, sync waves enforce this ordering:

| Wave | Component | Depends on |
|---|---|---|
| 0 | CouchDB Operator | OLM |
| 1 | External Secrets Operator + ClusterSecretStore | Wave 0 Healthy |
| 2 | StockTrader Operator (CRD + RBAC + manager) | Wave 1 Healthy |
| 3 | StockTrader CR (application instance) | Wave 2 Healthy |

ArgoCD itself must be bootstrapped manually before wave 0 begins — see [getting-started.md](getting-started.md).

## Networking

By default all application services communicate inside the cluster via `ClusterIP` services. External access is controlled by the `global.ingress` and `global.route` flags in the CR:

- `global.ingress: true` — creates a Kubernetes `Ingress` resource (for AKS with an ingress controller)
- `global.route: true` — creates an OpenShift `Route` resource
- `global.istio: true` — deploys Envoy sidecar injection and Istio `Gateway`/`VirtualService` resources

Only one of these should be enabled at a time.
