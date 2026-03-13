# Development Guide

How to build, test, and publish the stocktrader operator and its OLM bundle/catalog.

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| `operator-sdk` | ≥ 1.40 | Operator scaffolding and bundle generation |
| `docker` / `podman` | any | Build container images |
| `kubectl` + cluster access | any | Deploy and test locally |
| `kustomize` | ≥ 5.0 | Apply config overlays |
| `opm` | ≥ 1.28 | Build OLM file-based catalogs |

All build tooling that can be downloaded automatically is placed in `operator/bin/` by the corresponding make targets.

---

## Repository layout (operator core)

```
operator/
    Makefile              # All build targets — run from here or the repo root
    Dockerfile            # Operator manager image
    bundle.Dockerfile     # OLM bundle image
    catalog.Dockerfile    # OLM catalog (file-based catalog) image
    opm.Dockerfile        # opm tool image
    watches.yaml          # Maps StockTrader GVK → helm-charts/stocktrader/
    PROJECT               # Operator SDK project metadata
    helm-charts/
        stocktrader/      # Umbrella Helm chart
    config/
        crd/              # CRD manifest
        rbac/             # ClusterRole, bindings, service account
        manager/          # Deployment manifest for the operator manager
        default/          # Kustomization that composes CRD + RBAC + manager
        samples/          # Example StockTrader CR
    bundle/
        manifests/        # Generated ClusterServiceVersion and CRD copies
        metadata/         # OLM annotations.yaml
    catalog/              # File-based catalog (FBC) operator.yaml
    bin/                  # Downloaded tooling (kustomize, helm-operator, opm)
```

---

## Environment variables

All make targets accept these variables:

| Variable | Example | Description |
|---|---|---|
| `IMG` | `ghcr.io/myorg/stocktrader-operator:v1.2.0` | Operator manager image used by `docker-build`, `deploy`, `bundle` |
| `BUNDLE_IMG` | `ghcr.io/myorg/stocktrader-operator-bundle:v1.2.0` | Bundle image |
| `CATALOG_IMG` | `ghcr.io/myorg/stocktrader-operator-catalog:latest` | Catalog image |
| `VERSION` | `1.2.0` | Operator version used by `bundle` target |

Set them in the environment or pass on the command line:

```bash
export IMG=ghcr.io/myorg/stocktrader-operator:v1.2.0
make docker-build docker-push
```

---

## Make targets

All targets can be run from the repository root (the thin `Makefile` delegates to `operator/Makefile`) or from within `operator/` directly.

### Development

| Target | Description |
|---|---|
| `make help` | List all available targets with descriptions |
| `make run` | Run the operator locally against the cluster in `~/.kube/config` (no image build required) |
| `make install` | Install the CRD into the current cluster |
| `make uninstall` | Remove the CRD from the current cluster |

### Building

| Target | Description |
|---|---|
| `make docker-build IMG=<image>` | Build the operator manager image |
| `make docker-push IMG=<image>` | Push the operator manager image |
| `make docker-buildx IMG=<image>` | Build and push a multi-arch image (linux/amd64 + linux/arm64) |

### Deploying

| Target | Description |
|---|---|
| `make deploy IMG=<image>` | Deploy the operator (CRD + RBAC + manager) to the current cluster |
| `make undeploy` | Remove all operator resources from the current cluster |

### OLM bundle and catalog

| Target | Description |
|---|---|
| `make bundle IMG=<image>` | Generate the OLM bundle manifests (ClusterServiceVersion, annotations) |
| `make bundle-build BUNDLE_IMG=<image>` | Build the OLM bundle image |
| `make bundle-push BUNDLE_IMG=<image>` | Push the OLM bundle image |
| `make catalog-build CATALOG_IMG=<image>` | Build the file-based catalog image from `catalog/operator.yaml` |
| `make catalog-push CATALOG_IMG=<image>` | Push the catalog image |

---

## Local development workflow

The fastest inner loop for testing chart or watches changes:

```bash
# 1. Install the CRD
make install

# 2. Run the operator manager process locally (hot reload on restart)
make run IMG=<any-image>  # IMG is used for the CSV but not needed for run

# 3. In a separate terminal, apply a test CR
kubectl apply -f operator/config/samples/operators_v1_stocktrader.yaml

# 4. Modify helm-charts/stocktrader/, then kill and restart: make run
```

The operator will reconcile in your terminal, and you can see Helm rendering output directly. No image build is needed for chart-only changes.

---

## Building and deploying via Kustomize

Build and push the image, then patch the manager Deployment to use it:

```bash
IMG=ghcr.io/myorg/stocktrader-operator:dev make docker-build docker-push
IMG=ghcr.io/myorg/stocktrader-operator:dev make deploy
```

`make deploy` uses `kustomize edit set image` to update the manager Deployment's image reference in `config/manager/manager.yaml` before applying.

---

## OLM installation workflow

OLM allows cluster operators to install and upgrade operators via a subscription model. The full workflow:

### 1. Build and push the bundle image

```bash
VERSION=1.2.0
IMG=ghcr.io/myorg/stocktrader-operator:v${VERSION}
BUNDLE_IMG=ghcr.io/myorg/stocktrader-operator-bundle:v${VERSION}

make bundle IMG=${IMG} VERSION=${VERSION}
make bundle-build bundle-push BUNDLE_IMG=${BUNDLE_IMG}
```

### 2. Update the catalog

Edit `operator/catalog/operator.yaml` to add the new bundle entry, then build and push the catalog image:

```bash
CATALOG_IMG=ghcr.io/myorg/stocktrader-operator-catalog:latest
make catalog-build catalog-push CATALOG_IMG=${CATALOG_IMG}
```

### 3. Apply the CatalogSource and Subscription

Update the image reference in `operator/catalog-source.yaml` to point to your catalog image, then apply:

```bash
kubectl apply -f operator/catalog-source.yaml
kubectl apply -f operator/subscription.yaml
```

OLM will install the latest operator version from the catalog into the `stocktrader-operator-system` namespace.

---

## Updating the Helm chart

The operator is a thin wrapper around the Helm chart in `helm-charts/stocktrader/`. Chart changes do not require regenerating the OLM bundle unless the chart version, CRD schema, or permissions change.

Typical chart update workflow:

1. Edit templates in `helm-charts/stocktrader/templates/`
2. Bump `helm-charts/stocktrader/Chart.yaml` version
3. Test with `make run` locally
4. If new CRD fields are added, regenerate the bundle: `make bundle IMG=<image>`
5. Build and push: `make docker-build docker-push IMG=<image>`

---

## Adding a new microservice

1. Add a deployment template to `helm-charts/stocktrader/templates/`
2. Add corresponding values to `helm-charts/stocktrader/values.yaml`
3. Add the service's `enabled` flag and image fields to the CR spec in `config/samples/operators_v1_stocktrader.yaml`
4. If the service requires additional RBAC, update `config/rbac/`
5. Regenerate the bundle to update the CSV RBAC section: `make bundle IMG=<image>`

---

## Versioning conventions

This project follows [Semantic Versioning](https://semver.org/):

- **Patch** (`x.y.Z`) — bug fixes, dependency updates, no API changes
- **Minor** (`x.Y.0`) — new optional fields in the CR spec, new optional services
- **Major** (`X.0.0`) — breaking changes to required CR fields, CRD schema changes requiring migration

OLM bundle version must match the operator image tag. The CSV `replaces` field in `bundle/manifests/stocktrader-operator.clusterserviceversion.yaml` should point to the previous version to enable seamless upgrades.
