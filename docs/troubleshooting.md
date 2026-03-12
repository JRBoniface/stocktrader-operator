# Troubleshooting

Common problems, their causes, and how to resolve them.

---

## General diagnostic commands

```bash
# Operator pod logs
kubectl logs -n stocktrader-operator-system deploy/stocktrader-operator-controller-manager -c manager

# All events in a namespace (sorted by time)
kubectl get events -n stock-trader --sort-by='.lastTimestamp'

# ArgoCD application status
kubectl get applications -n argocd
argocd app get <app-name>

# ESO sync status
kubectl get clustersecretstore azure-kv
kubectl get externalsecret -n stock-trader
kubectl describe externalsecret <name> -n stock-trader

# OLM subscription status
kubectl get subscription -A
kubectl get installplan -A
kubectl get csv -A
```

---

## Platform operators

### OLM: Subscription stuck in `UpgradePending`

**Symptom:** `kubectl get subscription -A` shows `UpgradePending`; operator pod never starts.

**Cause:** The `InstallPlan` requires manual approval, or OLM cannot pull the bundle image.

**Fix:**
```bash
# Check the InstallPlan
kubectl get installplan -n <namespace>
kubectl describe installplan <name> -n <namespace>

# If approval is required
kubectl patch installplan <name> -n <namespace> \
  --type merge -p '{"spec":{"approved":true}}'

# If image pull fails — check the bundle image is accessible
kubectl get events -n <namespace> | grep -i pull
```

---

### ESO: `ClusterSecretStore` status `Invalid`

**Symptom:** `kubectl get clustersecretstore azure-kv` shows `Invalid`; ExternalSecret does not sync.

**Possible causes and fixes:**

1. **OIDC / Workload Identity misconfigured**
   ```bash
   kubectl describe clustersecretstore azure-kv
   # Look for: "could not authenticate to Azure" or "WorkloadIdentityCredential"
   ```
   Verify the ServiceAccount annotation and FederatedIdentityCredential in Terraform:
   - ServiceAccount must have annotation: `azure.workload.identity/client-id: <uai-client-id>`
   - FIC must reference the cluster's OIDC issuer URL and the correct namespace/SA name

2. **`config.env` value incorrect**
   ```bash
   kubectl get clustersecretstore azure-kv -o yaml | grep -A5 spec
   ```
   Check `tenantId` and `vaultUrl` match your Azure Key Vault. Regenerate from Terraform outputs if needed.

3. **ESO pods not running**
   ```bash
   kubectl get pods -n external-secrets
   kubectl logs -n external-secrets deploy/external-secrets
   ```

---

### ESO: Wave 1 fails on first ArgoCD sync

**Symptom:** `external-secrets-operator` ArgoCD Application shows `SyncFailed` with `no matches for kind "ClusterSecretStore"`.

**Cause:** This is expected on the first sync. The ESO Helm chart installs the `ClusterSecretStore` CRD in the same sync as the `ClusterSecretStore` object. The CRD may not be established before the object is applied.

**Fix:** No action needed. ArgoCD's retry policy (5 retries, 30 second backoff) will automatically re-sync once the CRD is established. If it does not recover after ~5 minutes, trigger a manual sync:
```bash
argocd app sync external-secrets-operator
```

---

### ESO: `ExternalSecret` in `SecretSyncedError` state

**Symptom:** `kubectl get externalsecret -n stock-trader` shows `SecretSyncedError`.

**Fix:**
```bash
kubectl describe externalsecret <name> -n stock-trader
# Common reasons:
# - Secret key not found in Key Vault — verify key names in Key Vault match the ExternalSecret spec
# - Forbidden — check the UAI has 'Key Vault Secrets User' role on the vault
# - NetworkError — check private endpoint / DNS resolution from the cluster nodes
```

---

### CouchDB Operator: pod stuck in `Pending`

**Symptom:** CouchDB operator pod never starts.

**Fix:**
```bash
kubectl describe pod -n couchdb -l app=couchdb-operator
# Common cause: namespace label missing for OperatorGroup
kubectl get operatorgroup -n couchdb -o yaml
```

Ensure the `OperatorGroup` in `platform-operators/couchdb/base/operator-group.yaml` targets the correct namespace.

---

### ArgoCD: Application perpetually `OutOfSync`

**Symptom:** An ArgoCD Application repeatedly shows `OutOfSync` even after successful sync.

**Common causes:**

1. **Server-side apply drift** — resources modified outside ArgoCD
   ```bash
   argocd app diff <app-name>
   ```

2. **`kustomize --enable-helm` not configured** — the ESO Kustomization uses `helmCharts` which requires the `--enable-helm` flag. This should be set automatically by the `argocd-instance.yaml`, but verify:
   ```bash
   kubectl get configmap argocd-cm -n argocd -o yaml | grep kustomizeBuildOptions
   # Should show: kustomizeBuildOptions: "--enable-helm"
   ```

3. **Helm-managed resources have mutating admission webhooks** — some operators mutate resource fields after apply. Add a `ignoreDifferences` entry in the Application spec for the affected field.

---

## Stocktrader operator

### Operator pod fails to start: `CrashLoopBackOff`

**Fix:**
```bash
kubectl logs -n stocktrader-operator-system deploy/stocktrader-operator-controller-manager -c manager
```

Common causes:
- `watches.yaml` references a non-existent chart path — verify `helm-charts/stocktrader/` is present in the operator image
- RBAC insufficient — check ClusterRole allows `get`/`list`/`watch` on `stocktraders` resources

---

### StockTrader CR stuck in `ReconcileFailed`

**Symptom:** `kubectl get stocktrader -n stock-trader` shows an error status.

**Fix:**
```bash
kubectl describe stocktrader <name> -n stock-trader
kubectl logs -n stocktrader-operator-system deploy/stocktrader-operator-controller-manager -c manager | tail -50
```

Common causes:

1. **Credentials secret not found** — ESO has not yet synced the secret. Check `kubectl get externalsecret` health.

2. **Helm rendering error** — invalid value in the CR spec.
   ```bash
   # Test Helm rendering locally
   helm template test stocktrader-operator/helm-charts/stocktrader/ -f <your-values.yaml>
   ```

3. **Image pull failure** — the application service images cannot be pulled.
   ```bash
   kubectl get events -n stock-trader | grep -i pull
   kubectl get pods -n stock-trader
   ```

---

### Application pods `CrashLoopBackOff`

**Fix:**
```bash
kubectl logs -n stock-trader <pod-name> --previous
kubectl describe pod -n stock-trader <pod-name>
```

Common causes:
- Database connection refused — check `spec.database.host` and `spec.database.port` in the CR
- Credentials secret has wrong key names — verify the secret keys match what the chart expects
- Redis connection refused — check `spec.redis.urlWithCredentials`

---

### Database connectivity issues

**Symptom:** Portfolio or trade-history pods fail with `Connection refused` or `SSL handshake failed`.

**Fix:**
```bash
# Test connectivity from within the cluster
kubectl run -it --rm debug --image=alpine --restart=Never -n stock-trader -- sh
# Inside the pod:
nc -zv <db-host> 5432

# Check SSL setting
kubectl get stocktrader <name> -n stock-trader -o jsonpath='{.spec.database.ssl}'
# For Azure Database for PostgreSQL, ssl should be true and port 5432
```

---

## Kustomize / build

### `error: accumulating resources: unable to find one of...`

**Cause:** A relative path in a `kustomization.yaml` does not resolve (e.g. after a directory was moved).

**Fix:**
```bash
kustomize build <path> 2>&1 | head -20
```
Check all `resources:` entries in the failing Kustomization and ensure paths are correct relative to the file's directory.

---

### `helmCharts requires --enable-helm flag`

**Cause:** Running `kustomize build` without `--enable-helm` on a Kustomization that includes `helmCharts`.

**Fix:**
```bash
kustomize build platform-operators/external-secrets/base --enable-helm
# Or with kubectl:
kubectl apply -k platform-operators --enable-helm
```

---

### `make deploy` fails with permission denied

**Cause:** The container registry requires authentication.

**Fix:**
```bash
# Docker Hub / GHCR
docker login ghcr.io

# Azure Container Registry
az acr login --name <registry-name>

# Then retry
make docker-push IMG=<image>
```

---

## Getting more help

1. Check the [operator-sdk](https://sdk.operatorframework.io/docs/) documentation for Helm operator behaviour
2. Check the [ESO documentation](https://external-secrets.io/latest/) for ClusterSecretStore and ExternalSecret spec details
3. Open an issue in [IBMStockTrader/stocktrader-operator](https://github.com/IBMStockTrader/stocktrader-operator/issues) with the output of:
   ```bash
   kubectl get stocktrader -A -o yaml
   kubectl get externalsecret -A -o yaml
   kubectl get clustersecretstore -o yaml
   kubectl logs -n stocktrader-operator-system deploy/stocktrader-operator-controller-manager -c manager
   ```
