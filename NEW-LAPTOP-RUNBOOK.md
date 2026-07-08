# New Laptop Runbook — Clone to Running App (Manual Steps)

This is the exact command sequence for getting CredPay running from a
**brand-new laptop**, assuming the Azure infrastructure (AKS, ACR,
PostgreSQL) **already exists** — i.e. a teammate joining the project, not
someone setting up a brand-new Azure subscription. All commands are
PowerShell.

If you instead need to provision a **new** Azure environment from scratch
(new subscription, new AKS/ACR/Postgres), do that first — see the Appendix
at the bottom and `PORTABILITY.md` — then come back here.

The real values for **this** project's existing infra (confirmed live, as of
this writing) are used throughout as concrete examples:

| Thing | Value |
|---|---|
| Resource group (AKS) | `rg-credpay` |
| AKS cluster name | `aks-credpay` |
| ACR name | `credproj` |
| ACR login server | `credproj.azurecr.io` |
| Postgres FQDN | `psql-credpay.postgres.database.azure.com` |
| Azure region | `canadacentral` |

---

## 0. Install prerequisites on the new laptop

| Tool | Needed for | Check it's installed |
|---|---|---|
| Git | Cloning the repo | `git --version` |
| Azure CLI | Everything Azure-related | `az --version` |
| kubectl | Talking to the cluster | `kubectl version --client` |
| Docker Desktop | *Only* if building/pushing images manually instead of via the pipeline | `docker --version` |
| Terraform CLI | *Only* if this laptop will run `terraform apply`/`terraform output` | `terraform --version` |

`az aks install-cli` will install `kubectl` for you if it's missing.

---

## 1. Clone the repo

```powershell
git clone https://github.com/Bharathreddyd3297/CredApp.git
cd CredApp
```

---

## 2. Log in to Azure

```powershell
az login

# If the account has more than one subscription, pick the right one
az account list --output table
az account set --subscription "Azure subscription 1"
az account show --output table
```

---

## 3. Connect kubectl to the existing AKS cluster

```powershell
az aks get-credentials `
  --resource-group rg-credpay `
  --name aks-credpay `
  --overwrite-existing

# Verify — should list the cluster's nodes
kubectl get nodes
```

If you don't know the resource group / cluster name off-hand (e.g. they
changed), get them from Terraform instead:

```powershell
cd terraform
terraform init          # connects to the existing remote state, does not create anything
terraform output -raw resource_group_name
terraform output -raw aks_cluster_name
cd ..
```

---

## 4. Connect AKS to ACR (so pods can pull images)

This is a **cluster-level** setting, not a laptop-level one — it only needs
to be run **once ever**, by anyone, for a given AKS cluster. It is already
done for `aks-credpay` / `credproj`. Only run this if you're not sure it's
been done (e.g. brand-new cluster), or after recreating the cluster. It's
safe to re-run — it's idempotent.

```powershell
az aks update --resource-group rg-credpay --name aks-credpay --attach-acr credproj
```

This grants the AKS kubelet identity `AcrPull` on the registry, so pods can
pull images with **no `imagePullSecrets`** needed in any manifest.

---

## 5. (Optional) Log Docker in to ACR — only if building/pushing images manually

Normally you don't need this: pushing to `main` triggers the Azure DevOps
pipeline (`Pipelines/dockerstage.yml`), which builds and pushes all three
images automatically. Only do this if you want to test an image locally
before pushing code, or push a one-off image by hand.

```powershell
az acr login --name credproj

docker build -t credproj.azurecr.io/credpay/frontend:latest ./frontend-react
docker build -t credproj.azurecr.io/credpay/user-service:latest ./user-service
docker build -t credproj.azurecr.io/credpay/payment-service:latest ./payment-service

docker push credproj.azurecr.io/credpay/frontend:latest
docker push credproj.azurecr.io/credpay/user-service:latest
docker push credproj.azurecr.io/credpay/payment-service:latest
```

---

## 6. Verify the images the pipeline built are actually in ACR

```powershell
az acr repository list --name credproj --output table

az acr repository show-tags --name credproj --repository credpay/frontend --output table
az acr repository show-tags --name credproj --repository credpay/user-service --output table
az acr repository show-tags --name credproj --repository credpay/payment-service --output table
```

---

## 7. Deploy the Kubernetes manifests — exact sequence

Order matters: namespace and config before anything else; DB schema before
the backends start (they run with `ddl-auto=validate`, so the tables must
already exist); backends before the frontend/ingress.

```powershell
# 1. Namespace
kubectl apply -f k8s/namespace/namespace.yaml

# 2. ConfigMap — already has the real Postgres FQDN baked in for this infra,
#    no edits needed as long as you're using the existing shared environment
kubectl apply -f k8s/configmap/configmap.yaml

# 3. Secret — create OUT-OF-BAND. Do NOT `kubectl apply -f k8s/secrets/secret.yaml`
#    directly — that file is a documentation-only example with placeholder
#    values and would overwrite the real password with "REPLACE_ME".
#    Get the real password from whoever provisioned Postgres, or if you
#    have Terraform state access:
#      terraform -chdir=terraform output -raw postgres_admin_password
kubectl create secret generic credpay-db `
  --namespace credpay `
  --from-literal=DB_PASSWORD="<real-postgres-password>" `
  --from-literal=SPRING_DATASOURCE_PASSWORD="<real-postgres-password>"

# 4. Database schema — ONE-TIME only. Skip this step entirely if the schema
#    was already applied by someone else against this same Postgres server
#    (re-running is harmless — schema.sql drops/recreates tables — but
#    don't do it against a database with data you want to keep).
kubectl create configmap db-schema `
  --namespace credpay `
  --from-file=schema.sql=schema.sql
kubectl apply -f k8s/postgres/schema-init-job.yaml
kubectl wait --for=condition=complete job/db-schema-init -n credpay --timeout=120s

# 5. Backends
kubectl apply -f k8s/user-service/
kubectl apply -f k8s/payment-service/

# 6. Frontend
kubectl apply -f k8s/frontend/

# 7. Ingress
kubectl apply -f k8s/ingress/ingress.yaml
```

---

## 8. Verify everything is running

```powershell
kubectl get pods -n credpay
kubectl get svc -n credpay
kubectl get ingress -n credpay
kubectl get hpa -n credpay

# Get the public IP the app is reachable on
kubectl get svc -n ingress-nginx ingress-nginx-controller `
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

All pods should show `Running` and `READY 1/1` (or `2/2` if a pod has a
sidecar — it doesn't here). The Ingress should show an `ADDRESS` — that's
the URL to browse to.

---

## 9. Test end-to-end

Browse to `http://<INGRESS_IP>/` and walk through: register → login → add
card → pay → payment history. For a scripted curl-based version of the same
flow (useful for quick sanity checks without opening a browser), see
`STAGE1-CHANGES.md` §6.

---

## 10. Redeploying after a code change

After pushing code and letting the pipeline build + push new `:latest`
images:

```powershell
kubectl rollout restart deployment/frontend -n credpay
kubectl rollout restart deployment/user-service -n credpay
kubectl rollout restart deployment/payment-service -n credpay

kubectl rollout status deployment/frontend -n credpay
kubectl rollout status deployment/user-service -n credpay
kubectl rollout status deployment/payment-service -n credpay
```

All three Deployments use `imagePullPolicy: Always`, so this always pulls
the freshly-pushed image rather than reusing a stale cached one.

---

## Quick diagnostics if something doesn't come up

```powershell
kubectl describe pod <pod-name> -n credpay
kubectl logs deployment/frontend -n credpay
kubectl logs deployment/user-service -n credpay
kubectl logs deployment/payment-service -n credpay
kubectl logs job/db-schema-init -n credpay
kubectl exec -it deployment/user-service -n credpay -- sh
```

---

## Appendix: this is a BRAND NEW Azure environment, not the existing shared one

If you're setting up an entirely new subscription/AKS/ACR/Postgres (not
connecting to the infra listed at the top of this file), you need an extra
step **before** §3 above: provision the infra with Terraform, and update a
few hardcoded values for the new environment. Summary (full detail in
`PORTABILITY.md`):

```powershell
cd terraform
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: subscription_id, location
# edit main.tf line 7: name_prefix (must be globally unique across Azure)
# edit backend.tf: point at your own pre-created remote-state storage account
terraform init
terraform apply
cd ..

# Create your own ACR (if you don't already have one) and attach it
az aks update --resource-group <your-rg> --name <your-aks-name> --attach-acr <your-acr-name>
```

Then, **before** §7 above, update these files with your new environment's
real values:
- `k8s/configmap/configmap.yaml` — `DB_HOST` / `SPRING_DATASOURCE_URL` from
  `terraform output -raw postgres_fqdn`
- `k8s/frontend/deployment.yaml`, `k8s/user-service/deployment.yaml`,
  `k8s/payment-service/deployment.yaml` — the `image:` line, replacing
  `credproj.azurecr.io` with `<your-acr-name>.azurecr.io`

And update `azure-pipelines.yml` / `Pipelines/dockerstage.yml` with your own
Azure DevOps service connection names so the pipeline can build and push to
*your* ACR. Full checklist: `PORTABILITY.md`.
