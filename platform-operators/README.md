# Platform Operators

This directory contains manifests to bootstrap ArgoCD onto the cluster. Once ArgoCD is running, it takes over management of the Stock Trader application via the GitOps manifests in [`gitops/`](../gitops/).

## Contents

```
platform-operators/
    kustomization.yaml      # Empty — ArgoCD is bootstrapped directly, not via this file
    argocd/
        base/               # ArgoCD Operator (OLM) + ArgoCD instance
        overlays/
            azure/          # AKS-specific overlay
```

## Bootstrap Sequence

Apply these steps once before using GitOps. All subsequent deployments (ESO, CouchDB, stocktrader) are managed by ArgoCD after step 6.

```bash
# Step 1 — Install OLM (if not already present)
curl -sL https://github.com/operator-framework/operator-lifecycle-manager/releases/latest/download/install.sh | bash -s <version>
kubectl get pods -n olm

# Step 2 — Install ESO via Helm
# See operator/helm-charts/external-secrets/README.md

# Step 3 — Apply ESO post-install manifests (ServiceAccount, ClusterSecretStore, ExternalSecrets)
# See operator/helm-charts/external-secrets/README.md

# Step 4 — Install CouchDB via Helm
# See operator/helm-charts/couchdb/README.md

# Step 5 — Install the ArgoCD Operator via OLM
kubectl apply -k platform-operators/argocd/overlays/azure

# Wait for the operator CSV to reach Succeeded
kubectl get csv -n argocd -w

# Step 6 — Create the ArgoCD instance
kubectl apply -f platform-operators/argocd/base/argocd-instance.yaml
kubectl wait --for=condition=Ready argocd/argocd -n argocd --timeout=300s

# Step 7 — Hand control to ArgoCD
kubectl apply -f gitops/app-of-apps.yaml
```

