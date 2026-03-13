# Helm Charts

This directory contains Helm charts for deploying the Stock Trader application and its dependencies.

## Contents

| Chart | Purpose | Details |
|---|---|---|
| [`stocktrader/`](stocktrader/) | Umbrella Helm chart for the Stock Trader microservices | Managed by the stocktrader operator |
| [`external-secrets/`](external-secrets/README.md) | External Secrets Operator — syncs secrets from Azure Key Vault | Install before CouchDB and the operator |
| [`couchdb/`](couchdb/README.md) | Apache CouchDB | Install after ESO credentials are provisioned |

## Install Order

Dependencies must be installed before the Stock Trader operator:

1. **ESO** — see [external-secrets/README.md](external-secrets/README.md)
2. **CouchDB** — see [couchdb/README.md](couchdb/README.md)
3. **Stock Trader Operator** — see [stocktrader/README.md](stocktrader/README.md)

The `stocktrader/` chart is not installed directly — it is managed by the Kubernetes operator via the `StockTrader` CR. See the [root README](../../README.md) for the full deployment sequence.
