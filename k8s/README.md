# CredPay — Kubernetes Manifests

Plain Kubernetes manifests that deploy the **CredPay** application onto the AKS
cluster provisioned by the `terraform/` project. Everything runs in the
`credpay` namespace and is exposed through a single ingress-nginx entry point.

No Helm, no Kustomize, no GitOps — just `kubectl apply`. This is a Phase 1
classroom capstone, kept intentionally simple.

## How this fits with Terraform

**Terraform (the `terraform/` project) creates the Azure infrastructure:**

- Resource Group
- Virtual Network
- **AKS** cluster
- **Azure PostgreSQL** Flexible Server
- **Log Analytics** Workspace

**Kubernetes (this project) deploys the application onto that AKS cluster:**

- Namespace
- ConfigMap
- Secret
- PostgreSQL schema Job
- Deployments (frontend, user-service, payment-service)
- Services
- Ingress

**Container images** are pulled from the **existing** Azure Container Registry
`credproj.azurecr.io` (it is *not* created by Terraform). AKS must be attached
to it once, out-of-band:

```bash
az aks update --attach-acr credproj
```

That grants the AKS kubelet identity `AcrPull`, so **no `imagePullSecrets` are
needed**. There is **no Azure Key Vault, no Workload Identity, and no
Managed Identity** in Phase 1 — the app authenticates to PostgreSQL with a
username + password stored in a Kubernetes Secret.

## Architecture

```
                       Internet
                          │
                   ┌──────▼───────┐
                   │ Ingress      │  (ingress-nginx, no host -> LoadBalancer public IP)
                   │  credpay     │
                   └──┬────┬────┬─┘
          /api/payment│    │    │/  (everything else)
          /api/users  │    │    │
          /api/cards  │    │    │
             ┌────────▼┐ ┌─▼──────────┐ ┌▼──────────┐
             │ payment │ │  user-     │ │ frontend  │
             │ service │ │  service   │ │ (React/   │
             │(FastAPI │ │ (Spring    │ │  Nginx)   │
             │ :8000)  │ │  Boot      │ │  :80      │
             └────┬────┘ │  :8080)    │ └───────────┘
                  │      └─────┬──────┘
                  └──────┬─────┘
                         │ sslmode=require
                ┌────────▼─────────┐
                │ Azure PostgreSQL │  (Flexible Server, managed by Terraform)
                │  Flexible Server │
                └──────────────────┘

  Images: credproj.azurecr.io/credpay/{frontend,user-service,payment-service}:latest
```

## Directory layout

| Path | Kind | Purpose |
|------|------|---------|
| `namespace/namespace.yaml` | Namespace | `credpay` namespace (Pod Security = `baseline`) |
| `configmap/configmap.yaml` | ConfigMap | Non-secret DB coordinates + Spring datasource URL (`credpay-config`) |
| `secrets/secret.yaml` | Secret | **Example only** — DB credentials (`credpay-db`); create the real one out-of-band |
| `postgres/schema-init-job.yaml` | Job | One-shot job that applies `schema.sql` to PostgreSQL before backends start |
| `frontend/` | Deployment, Service, HPA | React SPA served by Nginx on `:80` |
| `user-service/` | Deployment, Service, HPA | Spring Boot / Java 21 REST API on `:8080` |
| `payment-service/` | Deployment, Service, HPA | FastAPI / Python 3 REST API on `:8000` |
| `ingress/ingress.yaml` | Ingress | Host-less, path-based routing to all three services |

## Prerequisites

- Terraform applied, and `kubectl` pointed at the AKS cluster:
  ```bash
  az aks get-credentials \
    --resource-group $(terraform -chdir=../terraform output -raw resource_group_name) \
    --name $(terraform -chdir=../terraform output -raw aks_cluster_name) \
    --overwrite-existing
  ```
- AKS attached to the ACR: `az aks update --attach-acr credproj`
- **ingress-nginx** controller installed in the cluster.
- **metrics-server** running (built into AKS) — required by the HPAs.
- Images pushed to `credproj.azurecr.io`:
  `credpay/frontend`, `credpay/user-service`, `credpay/payment-service`.

## Hardcoded values (no placeholders left)

Both the ACR login server and the PostgreSQL host are already filled in with
real values, so the manifests can be applied as-is:

| Value | Found in | Current value |
|-------|----------|----------------|
| ACR login server | `frontend/`, `user-service/`, `payment-service/` Deployments | `credproj.azurecr.io` |
| PostgreSQL FQDN | `configmap/configmap.yaml` | `psql-credpay.postgres.database.azure.com` |

If either Azure resource is ever renamed, re-run
`terraform -chdir=../terraform output -raw postgres_fqdn` (or the ACR name)
and update these files directly - there is no templating step.

## Secret

`secrets/secret.yaml` is an **example** with `REPLACE_ME` values — never commit a
real password. Create the Secret directly in the cluster from the Terraform
output instead:

```bash
kubectl create secret generic credpay-db \
  --namespace credpay \
  --from-literal=DB_PASSWORD="$(terraform -chdir=../terraform output -raw postgres_admin_password)" \
  --from-literal=SPRING_DATASOURCE_PASSWORD="$(terraform -chdir=../terraform output -raw postgres_admin_password)"
```

Phase 1 uses this plain Kubernetes Secret only — no Key Vault, no CSI driver.

## Deployment order

Apply in this order — config and schema must exist before the backends start:

```bash
# 1. Namespace
kubectl apply -f namespace/namespace.yaml

# 2. ConfigMap  (already has the real Postgres FQDN filled in)
kubectl apply -f configmap/configmap.yaml

# 3. Secret  (create out-of-band from terraform output — see "Secret" above)

# 4. Schema Job — first create the schema ConfigMap from the repo's schema.sql:
kubectl create configmap db-schema \
  --namespace credpay \
  --from-file=schema.sql=../schema.sql
kubectl apply -f postgres/schema-init-job.yaml
kubectl wait --for=condition=complete job/db-schema-init -n credpay --timeout=120s

# 5. User Service
kubectl apply -f user-service/

# 6. Payment Service
kubectl apply -f payment-service/

# 7. Frontend
kubectl apply -f frontend/

# 8. Ingress
kubectl apply -f ingress/ingress.yaml
```

> The `user-service` runs with `spring.jpa.hibernate.ddl-auto=validate`, so the
> tables **must** already exist — that is why the schema Job (step 4) runs before
> the backends.

## Ingress routing

The Ingress has **no host** — it answers on the ingress controller's public
LoadBalancer IP over HTTP. (Add a DNS name + TLS in a later phase.)

| Path | Backend | Port |
|------|---------|------|
| `/api/payment` | payment-service | 8000 |
| `/api/users` | user-service | 8080 |
| `/api/cards` | user-service | 8080 |
| `/` (everything else) | frontend | 80 |

Because all traffic is same-origin behind the ingress, the frontend uses relative
`/api/...` calls and **no CORS is required**. Build the frontend with empty
`VITE_USER_API_URL` / `VITE_PAYMENT_API_URL`.

## Autoscaling (HPA)

All three workloads scale on CPU (user-service also on memory), `min 2 / max 6`,
with a 300s scale-down stabilization window. Requires metrics-server.

| Service | Target |
|---------|--------|
| frontend | CPU 70% |
| user-service | CPU 75% + memory 80% |
| payment-service | CPU 75% |

## Verify

```bash
# Pods
kubectl get pods -n credpay

# PostgreSQL connectivity (the schema Job proves it end-to-end)
kubectl get job db-schema-init -n credpay
kubectl logs job/db-schema-init -n credpay

# Ingress — grab the public IP
kubectl get ingress credpay -n credpay
INGRESS_IP=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl http://$INGRESS_IP/
```

Then browse to `http://<INGRESS_IP>/`.

## Notes / current limitations

- **No Workload Identity / Managed Identity.** The app uses a DB username +
  password from the `credpay-db` Secret. This matches the Terraform Phase 1
  project, which does not provision any Azure identity resources.
- **Frontend runs as root** (`runAsNonRoot: false`) because `nginx:stable-alpine`
  binds `:80`, so namespace Pod Security is `baseline`. Backends run non-root
  with a read-only root filesystem and a writable `/tmp` `emptyDir`.
- **Image pull** relies on `az aks update --attach-acr credproj`; there are no
  `imagePullSecrets`.
- **`imagePullPolicy: Always`** on all three app Deployments. All three are
  pushed to the mutable `:latest` tag, so `IfNotPresent` would let a node
  keep running a stale cached image after `kubectl rollout restart` -
  `Always` guarantees the freshly-pushed image is pulled every time.
- The schema Job is **safe to re-run** — `schema.sql` drops/recreates tables.
