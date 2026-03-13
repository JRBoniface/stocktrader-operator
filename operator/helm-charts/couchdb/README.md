# CouchDB — Installation

Installs [Apache CouchDB](https://couchdb.apache.org/) via the [official Helm chart](https://github.com/apache/couchdb-helm).

> **Future:** This chart is planned as a dependency of the `stocktrader` umbrella Helm chart (`helm-charts/stocktrader/Chart.yaml`). When promoted, the values in `values.yaml` will move into `stocktrader/values.yaml` under a `couchdb:` key.

---

## Prerequisites

CouchDB credentials must exist as a Kubernetes Secret named `couchdb-credentials` in the `couchdb` namespace **before installing**. This Secret is managed by the External Secrets Operator.

Follow the **CouchDB Credentials** section in [helm-charts/external-secrets/README.md](../external-secrets/README.md) to provision the ExternalSecret, then verify the Secret exists:

```bash
kubectl get secret couchdb-credentials -n couchdb
```

---

## Install

```bash
helm repo add apache-couchdb https://apache.github.io/couchdb-helm
helm repo update

helm upgrade --install couchdb apache-couchdb/couchdb \
  --namespace couchdb \
  --create-namespace \
  --version 4.6.3 \
  -f helm-charts/couchdb/values.yaml
```

---

## Verify

```bash
kubectl get pods -n couchdb
kubectl get pvc -n couchdb

# CouchDB should respond on its service
kubectl port-forward svc/couchdb-svc-couchdb 5984:5984 -n couchdb &
curl http://localhost:5984/_up
```
