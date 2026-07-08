# Stage 1 — Make CredPay Run on AKS (Manual Deployment)

This document records every change made to take CredPay from "pods are
running but the app doesn't work" to "fully functional inside AKS via manual
`kubectl apply`". It is written to double as teaching material: every change
states the **problem**, the **fix**, and **why** it matters for Kubernetes /
Docker / Azure DevOps students.

Scope: Stage 1 only. No CI/CD deployment, no Helm, no GitOps, no TLS, no
Key Vault, no Workload Identity — those are Stage 2/3.

---

## 1. Root cause of the AKS blocker

> "Frontend still calls localhost. Application does not function correctly
> inside AKS."

**Root cause:** [frontend-react/src/services/api.js](frontend-react/src/services/api.js)
built its axios `baseURL`s as:

```js
const USER_BASE_URL = import.meta.env.VITE_USER_API_URL || 'http://localhost:8080';
const PAYMENT_BASE_URL = import.meta.env.VITE_PAYMENT_API_URL || 'http://localhost:8000';
```

Vite inlines `import.meta.env.VITE_*` values **at build time**, not at
container runtime. The Docker build pipeline
([Pipelines/dockerstage.yml](Pipelines/dockerstage.yml)) never passes
`VITE_USER_API_URL` / `VITE_PAYMENT_API_URL` as build args, and `.env` files
are excluded from the Docker build context
([frontend-react/.dockerignore](frontend-react/.dockerignore)). So every
image built by CI got the `localhost` fallback **permanently baked into the
shipped JavaScript bundle**. Once that bundle runs in a user's browser, it
tries to call `http://localhost:8080` — the user's own laptop, not the AKS
cluster — and every API call fails.

The rest of the architecture (Ingress path-based routing, K8s Service names,
ConfigMap/Secret wiring) was already correctly designed for a same-origin,
Ingress-routed deployment. Only the frontend's fallback defaults were wrong.

---

## 2. Files modified

| # | File | Why |
|---|------|-----|
| 1 | `frontend-react/src/services/api.js` | **The fix.** Default to relative URLs instead of `localhost`. |
| 2 | `frontend-react/.env.example` | Document when `localhost` values are (and aren't) appropriate. |
| 3 | `frontend-react/README.md` | Correct stale docs that described `localhost` as the default. |
| 4 | `k8s/frontend/deployment.yaml` | Restore dropped container `securityContext`; fix `imagePullPolicy`. |
| 5 | `k8s/user-service/deployment.yaml` | Fix `imagePullPolicy`. |
| 6 | `k8s/payment-service/deployment.yaml` | Fix `imagePullPolicy`. |
| 7 | `k8s/README.md` | Correct stale placeholder docs; document `imagePullPolicy` change. |

Files reviewed and found already correct — **no changes made** (see §3):
`k8s/configmap/configmap.yaml`, `k8s/secrets/secret.yaml`,
`k8s/namespace/namespace.yaml`, `k8s/ingress/ingress.yaml`,
`k8s/*/service.yaml`, `k8s/*/hpa.yaml`, `k8s/postgres/schema-init-job.yaml`,
`user-service/src/.../CorsConfig.java`, `user-service/.../application.properties`,
`payment-service/app/main.py`, `payment-service/app/database.py`,
`frontend-react/vite.config.js`, `frontend-react/nginx.conf`, all three
`Dockerfile`s, `azure-pipelines.yml`, `Pipelines/dockerstage.yml`, `terraform/`.

> Note: `k8s/configmap|secrets|namespace|ingress/*.yaml` show as "modified" in
> `git diff` because they were already mid-edit in the working tree before
> this session started (simplifying away Workload Identity/TLS placeholders
> that Terraform doesn't provision, and filling in the real ACR/Postgres
> hostnames). Those edits were reviewed, found correct, and left as-is.

---

## 3. Detailed changes

### 3.1 `frontend-react/src/services/api.js` — the fix

**Before:**
```js
const USER_BASE_URL = import.meta.env.VITE_USER_API_URL || 'http://localhost:8080';
const PAYMENT_BASE_URL = import.meta.env.VITE_PAYMENT_API_URL || 'http://localhost:8000';
```

**After:**
```js
const USER_BASE_URL = import.meta.env.VITE_USER_API_URL || '';
const PAYMENT_BASE_URL = import.meta.env.VITE_PAYMENT_API_URL || '';
```

**Why this works:** `axios.create({ baseURL: '' })` resolves requests
(`/api/users/login`, `/api/payment/pay`, ...) against the page's own origin.
Behind the Ingress, the frontend and both backends are reached through the
**same origin** (the Ingress LoadBalancer IP), and `k8s/ingress/ingress.yaml`
already path-routes `/api/payment` → payment-service, `/api/users` and
`/api/cards` → user-service, `/` → frontend. No CORS is needed because the
browser never makes a cross-origin request. Local `npm run dev` is
unaffected: a developer who copies `.env.example` to `.env` still gets
absolute `localhost` URLs for the Vite dev server workflow.

### 3.2 `frontend-react/.env.example`

Added a comment block clarifying that this file is for **local development
only** (`npm run dev`), and that Docker/CI must never see a real `.env` (this
was already true — `.dockerignore` excludes `.env*` — but wasn't documented,
inviting someone to "fix" the AKS issue by reintroducing a baked-in
`localhost` value).

### 3.3 `frontend-react/README.md`

Updated the "Backend configuration" and "Docker" sections, which described
`localhost:8080` / `localhost:8000` as defaults. They now state that relative
URLs are the default (needed for Docker/AKS) and `localhost` is the opt-in
override for local dev via `.env`.

### 3.4 `k8s/frontend/deployment.yaml`

**Problem 1 — dropped security hardening.** A prior in-progress edit in this
repo removed Azure Workload Identity from this file (correct — Terraform
doesn't provision the identity resources it needs) but accidentally deleted
the container-level `securityContext` in the same edit:

```yaml
# deleted by mistake:
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
    add: ["NET_BIND_SERVICE"]
```

This pod must run as root (`runAsNonRoot: false` at the pod level) because
`nginx:stable-alpine`'s master process binds port 80. But "runs as root"
doesn't have to mean "has every Linux capability" — dropping all capabilities
and adding back only `NET_BIND_SERVICE` (the one needed to bind a privileged
port) is the standard least-privilege pattern for this exact scenario, and is
explicitly allowed under the namespace's `pod-security.kubernetes.io/enforce:
baseline` label. **Restored.**

**Problem 2 — stale image risk.** `imagePullPolicy: IfNotPresent` was paired
with the mutable `:latest` tag. `IfNotPresent` only checks whether a node
already has an image with that tag cached — it does **not** compare digests.
On a manual-deployment workflow (`kubectl apply` + `kubectl rollout restart`),
a node that already ran `credpay/frontend:latest` before would silently keep
serving the **old** code after a fresh push, even though ACR has the new
image. Changed to `imagePullPolicy: Always`.

### 3.5 / 3.6 `k8s/user-service/deployment.yaml`, `k8s/payment-service/deployment.yaml`

Same `imagePullPolicy: IfNotPresent` → `Always` fix, same reasoning — both
images are also pushed to the mutable `:latest` tag.

### 3.7 `k8s/README.md`

- Replaced the "one placeholder you must replace" section (which pointed at
  `<POSTGRES_FQDN>` in the ConfigMap) with a "hardcoded values" table, since
  that file was already filled in with the real hostname
  (`psql-credpay.postgres.database.azure.com`) and ACR
  (`credproj.azurecr.io`) — the doc was out of date.
- Documented the new `imagePullPolicy: Always` behavior under "Notes /
  current limitations".
- (Follow-up audit pass) Fixed a second, missed reference to the same stale
  placeholder in the "Deployment order" section — step 2 said
  `kubectl apply -f configmap/configmap.yaml  (after replacing <POSTGRES_FQDN>)`,
  which no longer applies.

### 3.8 `k8s/configmap/configmap.yaml` (follow-up audit pass)

The file's own header comment still said `Replace <POSTGRES_FQDN> with:
terraform output -raw postgres_fqdn` directly above data values that were
**already** the real hostname — a leftover instruction contradicting the
line right below it. Reworded to state the FQDN is already set, with the
`terraform output` command kept only as guidance for if the server is ever
recreated under a different name. No functional change (the ConfigMap's
`data:` values were untouched) — comment accuracy only.

---

## 4. Reviewed, no change needed (and why)

Being thorough means also recording what was checked and found correct:

- **`user-service/.../CorsConfig.java`** and **`payment-service/app/main.py`**
  hardcode `http://localhost:5173` as the only allowed CORS origin. This is
  correct for local dev (Vite dev server calling backends cross-origin) and
  **harmless in AKS**: once the frontend calls relative URLs (§3.1), the
  browser's request `Origin` header equals the page's own origin, so it's a
  same-origin request — CORS middleware is never invoked by the browser.
- **`user-service/.../application.properties`**
  (`spring.datasource.url=jdbc:postgresql://localhost:5432/credpay`) and
  **`payment-service/app/database.py`** (`DB_HOST` default `"localhost"`) are
  local-dev fallback defaults, not bugs. Spring Boot's environment-variable
  precedence ranks OS env vars above `application.properties`, and both
  Deployments inject `SPRING_DATASOURCE_URL` / `DB_HOST` via
  `envFrom: configMapRef: credpay-config` — the K8s value always wins in the
  cluster.
- **`k8s/ingress/ingress.yaml`, `k8s/configmap/configmap.yaml`,
  `k8s/secrets/secret.yaml`, `k8s/namespace/namespace.yaml`** — already
  correctly simplified to match what Terraform actually provisions (no TLS,
  no host, no Workload Identity, real ACR/Postgres hostnames). Reviewed and
  left as-is.
- **`frontend-react/nginx.conf`, `vite.config.js`, all three `Dockerfile`s,
  `.dockerignore`s** — multi-stage builds, non-root runtime users (backends),
  SPA fallback routing, gzip, and asset caching are all already correct for
  AKS. No changes needed.
- **`azure-pipelines.yml`** (Terraform stage) and
  **`Pipelines/dockerstage.yml`** (Docker build/push stage) — these are two
  separate Azure DevOps pipeline definitions in this repo. Neither references
  `VITE_*` build args, so the api.js fix in §3.1 changes their *output*
  (relative URLs baked in) without requiring any pipeline edit. Per the
  instructions for this task, pipelines were **not** redesigned.
- **`terraform/`** — `postgres_fqdn` output resolves to
  `psql-credpay.postgres.database.azure.com` (from `name_prefix = "credpay"`
  in `terraform/main.tf`), matching the hardcoded ConfigMap value exactly.
  Reviewed only, not modified.

---

## 5. Manual deployment guide

### 5.1 Verify locally (optional, before pushing)

```powershell
# Frontend
cd frontend-react
npm install
npm run build          # must succeed with NO .env file present
npm run preview

# User service
cd ../user-service
mvn -B clean package -DskipTests

# Payment service
cd ../payment-service
pip install -r requirements.txt
```

### 5.2 Build Docker images

```powershell
cd frontend-react
docker build -t credproj.azurecr.io/credpay/frontend:latest .

cd ../user-service
docker build -t credproj.azurecr.io/credpay/user-service:latest .

cd ../payment-service
docker build -t credproj.azurecr.io/credpay/payment-service:latest .
```

### 5.3 Push images to ACR

```powershell
az acr login --name credproj

docker push credproj.azurecr.io/credpay/frontend:latest
docker push credproj.azurecr.io/credpay/user-service:latest
docker push credproj.azurecr.io/credpay/payment-service:latest
```

(In practice this is what `Pipelines/dockerstage.yml` does automatically on
every push to `main` — these are the manual equivalents for local testing.)

### 5.4 Verify ACR

```powershell
az acr repository list --name credproj --output table
az acr repository show-tags --name credproj --repository credpay/frontend --output table
az acr repository show-tags --name credproj --repository credpay/user-service --output table
az acr repository show-tags --name credproj --repository credpay/payment-service --output table
```

### 5.5 Connect kubectl to the AKS cluster

```powershell
az aks get-credentials `
  --resource-group $(terraform -chdir=terraform output -raw resource_group_name) `
  --name $(terraform -chdir=terraform output -raw aks_cluster_name) `
  --overwrite-existing

# One-time only, if not already attached:
az aks update --resource-group <rg-name> --name <aks-name> --attach-acr credproj
```

### 5.6 Deploy to AKS (order matters)

```powershell
# 1. Namespace
kubectl apply -f k8s/namespace/namespace.yaml

# 2. ConfigMap (already has real values - no edits needed)
kubectl apply -f k8s/configmap/configmap.yaml

# 3. Secret - create OUT-OF-BAND from the Terraform output (never commit a real password)
kubectl create secret generic credpay-db `
  --namespace credpay `
  --from-literal=DB_PASSWORD="$(terraform -chdir=terraform output -raw postgres_admin_password)" `
  --from-literal=SPRING_DATASOURCE_PASSWORD="$(terraform -chdir=terraform output -raw postgres_admin_password)"

# 4. Schema Job - create the schema ConfigMap, then run the Job once
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

### 5.7 Redeploying after a code change (the normal loop)

```powershell
# ... after pushing new code and the pipeline pushes new :latest images ...
kubectl rollout restart deployment/frontend -n credpay
kubectl rollout restart deployment/user-service -n credpay
kubectl rollout restart deployment/payment-service -n credpay

kubectl rollout status deployment/frontend -n credpay
kubectl rollout status deployment/user-service -n credpay
kubectl rollout status deployment/payment-service -n credpay
```

Thanks to `imagePullPolicy: Always` (§3.4–3.6), this is now guaranteed to
pick up the freshly-pushed `:latest` image on every node.

### 5.8 Diagnostics toolkit

```powershell
kubectl get pods -n credpay
kubectl get svc -n credpay
kubectl get ingress -n credpay
kubectl get hpa -n credpay

kubectl describe pod <pod-name> -n credpay
kubectl logs deployment/frontend -n credpay
kubectl logs deployment/user-service -n credpay
kubectl logs deployment/payment-service -n credpay
kubectl logs job/db-schema-init -n credpay

kubectl exec -it deployment/user-service -n credpay -- sh
```

---

## 6. End-to-end validation checklist

```powershell
$INGRESS_IP = kubectl get svc -n ingress-nginx ingress-nginx-controller `
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo $INGRESS_IP
```

Browse to `http://<INGRESS_IP>/` and confirm:

- [ ] **Pods healthy** — `kubectl get pods -n credpay` shows all pods
      `Running` / `2/2` or `1/1` Ready, no `CrashLoopBackOff`.
- [ ] **Ingress has an address** — `kubectl get ingress -n credpay` shows the
      LoadBalancer IP under `ADDRESS`.
- [ ] **Frontend loads** — `http://<INGRESS_IP>/` renders the CredPay login
      page (not a blank page or nginx 404).
- [ ] **No localhost calls** — open browser DevTools → Network tab; confirm
      XHR requests go to `http://<INGRESS_IP>/api/...`, **not**
      `localhost:8080` / `localhost:8000`.
- [ ] **Register User** — `/register` creates a new account and shows a
      success message (proves user-service ↔ PostgreSQL works end-to-end).
- [ ] **Login** — log in with the account just created; redirects to
      `/dashboard` and session persists in `localStorage`.
- [ ] **Add Card** — `/add-card` submits successfully and the card appears
      on the dashboard.
- [ ] **Payment** — `/pay-bill` completes a payment and redirects to
      `/success` (proves payment-service ↔ PostgreSQL works end-to-end).
- [ ] **Payment History** — `/payment-history` lists the transaction just
      made.
- [ ] **Database verification** — confirm rows actually landed in Postgres:
      ```powershell
      kubectl run psql-client -n credpay --rm -it --restart=Never `
        --image=postgres:16-alpine -- `
        psql "host=psql-credpay.postgres.database.azure.com port=5432 dbname=credpay user=credpayadmin sslmode=require" `
        -c "select count(*) from users;" -c "select count(*) from payments;"
      ```
- [ ] **Ingress path routing** — verify each backend is reachable only
      through its intended path:
      ```powershell
      curl http://$INGRESS_IP/api/users/login -Method POST -Body '{}' -ContentType 'application/json'
      curl http://$INGRESS_IP/api/payment/history/1
      ```
- [ ] **Redeploy picks up new code** — push a trivial UI text change, wait
      for the pipeline to push a new `:latest` image, run
      `kubectl rollout restart deployment/frontend -n credpay`, and confirm
      the change is visible after `kubectl rollout status` completes (proves
      `imagePullPolicy: Always` is working).

---

## 7. Summary — how each change contributes to a working AKS deployment

| Change | Contribution |
|--------|--------------|
| `api.js` relative URLs | **The actual fix.** Lets one image work behind any Ingress IP, with no absolute backend URL ever baked into the bundle. |
| `.env.example` / README docs | Prevents the fix from being silently undone by someone adding a `.env` with `localhost` values for "convenience". |
| Frontend `securityContext` restored | Keeps the required root nginx process at least-privilege (capabilities dropped except `NET_BIND_SERVICE`), consistent with the namespace's `baseline` Pod Security level. |
| `imagePullPolicy: Always` (all 3 Deployments) | Guarantees `kubectl rollout restart` actually deploys the image just pushed to ACR, instead of silently reusing a stale cached one — critical for a manual-deploy workflow. |
| `k8s/README.md` accuracy fixes | Keeps the runbook trustworthy for whoever deploys next (a teammate, a student, or future-you in Stage 2). |
