# Stage 2 — Automate AKS Deployment via Azure DevOps Pipeline

This document records the CI/CD automation work added on top of Stage 1's
working manual `kubectl` deployment (see `STAGE1-CHANGES.md`), and — the
part worth touching base on — the three issues hit getting the pipeline's
Terraform stage to run green for the first time, with root cause and fix
for each. Written to double as teaching material, same as Stage 1.

Scope: `azure-pipelines.yml`, `terraform/modules/keyvault/`, the frontend
blue/green manifests, and the two additive health endpoints. No Helm, no
GitOps, no CSI driver, no Workload Identity — still `kubectl apply` and
`AzureCLI@2`, just triggered by a pipeline instead of by hand.

---

## 1. What was added

- **Terraform** — a `modules/keyvault/` module that looks up an
  out-of-band-created Key Vault (same pattern as the ACR) and writes the
  PostgreSQL host/database/username/password into it as four secrets.
- **Pipeline** — three stages: `Terraform` (apply infra + push secrets to
  Key Vault) → `DockerBuild` (unchanged) → `DeployToAKS` (read secrets back
  with `AzureKeyVault@2`, recreate the `credpay-db` Secret every run, run
  the schema Job, roll out user-service/payment-service via rolling update,
  roll out the frontend via blue/green, smoke-test the new color, flip
  traffic only on success, then print full cluster state).
- **Kubernetes** — `k8s/frontend/deployment.yaml`/`hpa.yaml` split into
  blue/green pairs; `frontend` Service's selector is flipped by the
  pipeline with `kubectl patch` after a passing smoke test.
- **App code** — `GET /api/users/health` (Spring) and
  `GET /api/payment/health` (FastAPI), added purely so the smoke test has
  real routes to call.

---

## 2. Troubleshooting log — first pipeline run

### 2.1 `terraform apply` failed: "subscription ID could not be determined"

**Symptom:**
```
/opt/hostedtoolcache/terraform/.../terraform apply -auto-approve -var=subscription_id= ...
Error: building account: unable to configure ResourceManagerAccount:
subscription ID could not be determined and was not specified
```
Note the `-var=subscription_id=` — empty, not missing.

**Root cause:** Azure DevOps only expands `$(variable)` macros into a
task's `inputs` (e.g. `TerraformTask@5`'s `commandOptions`) for **non-secret**
pipeline variables. `subscriptionId` had been added as a **secret** pipeline
variable, so the macro silently resolved to an empty string in that context
instead of substituting the real value — it only works for script `env:`
mappings, which `commandOptions` is not.

**Fix chosen (explicit decision for this capstone project):** commit the
real subscription ID into `terraform/terraform.tfvars` instead of passing
it through a pipeline variable. This required:
- Adding `!terraform/terraform.tfvars` to `.gitignore` (which otherwise
  blanket-excludes `*.tfvars`).
- Removing the now-redundant (and actively harmful) `-var="subscription_id=$(subscriptionId)"`
  override from `azure-pipelines.yml` — leaving it in would have kept
  clobbering the tfvars value with an empty string.

**Trade-off, on the record:** this reintroduces the exact exposure
`PORTABILITY.md` §A already documented and had previously fixed once before
— this repo's subscription ID leaked into git history via `terraform.tfvars`
on an earlier commit. Accepted here because it's a personal capstone
subscription, not a shared/public production one. **Revisit if this repo is
ever made public** — `PORTABILITY.md` has a 2026-07-09 update note on this.

**Alternative not taken:** simply mark the `subscriptionId` pipeline
variable **non-secret** in the Azure DevOps UI. That alone fixes the
macro-expansion problem with zero repo changes and no exposure. Worth
defaulting to this on future projects where the subscription ID actually
needs to stay out of git.

### 2.2 Key Vault resource group was wrong

`kv-credpay` was created in the **`CredProj`** resource group — the same
pre-existing bootstrap RG that holds the Terraform state storage account
(`credprojstate`) — not in `rg-credpay` (the app RG Terraform itself
creates). `terraform.tfvars` and `azure-pipelines.yml`'s
`keyVaultResourceGroup` variable were both initially guessed as
`rg-credpay`, which is a reasonable-looking default but wasn't how the
vault was actually provisioned. Fixed by correcting both to `CredProj`.

### 2.3 `terraform apply` failed: 403 Forbidden on Key Vault secrets

**Symptom:**
```
Error: checking for presence of existing Secret "postgres-db-name" ...
StatusCode=403 Code="Forbidden" Message="... does not have secrets get
permission on key vault 'kv-credpay' ..." InnerError={"code":"AccessDenied"}
```
This happened *after* granting `scnew2`'s service principal the
**`Key Vault Secrets Officer`** Azure RBAC role on the vault.

**Root cause:** `kv-credpay` uses the classic **vault access-policy**
permission model, not Azure RBAC. When a vault isn't switched into RBAC
mode (`enableRbacAuthorization = true`), Azure RBAC role assignments are
silently ignored for data-plane operations (get/set/list secrets) — only
the vault's own access-policy list is consulted. The role assignment
"succeeded" (no error creating it) but had no actual effect.

**Fix:**
```bash
az keyvault set-policy --name kv-credpay --object-id <scnew2-object-id> \
  --secret-permissions get list set delete
```
(Note for PowerShell: `\` line continuation doesn't work there like it
does in bash — either use backtick `` ` `` continuation or put the command
on one line.)

**Lesson for next time:** before assigning an RBAC role on a Key Vault,
check the permission model first:
```bash
az keyvault show --name <vault> --query properties.enableRbacAuthorization
```
`false`/empty → use `az keyvault set-policy`. `true` → an RBAC role
assignment is the right tool (and where `az role assignment create ...
--role "Key Vault Secrets Officer"` from §2.1's setup instructions applies).

### 2.4 Smoke test failed: `wget: can't connect to remote host: Connection refused`

**Symptom:** everything up through the blue/green rollout succeeded -
`terraform apply`, Docker build/push, `Get AKS Credentials`, schema Job,
user-service, payment-service, `frontend-green` rollout all completed
cleanly (`kubectl rollout status` reported Ready). The Smoke Test step then
failed on the very first check:
```
Smoke testing pod: frontend-green-68f86fb7b6-pmwlf (version=green)
GET / (frontend)
wget: can't connect to remote host: Connection refused
FAILED: / (frontend)
```
The safety mechanism did its job correctly here: because the smoke test
failed, the pipeline never patched the `frontend` Service's selector, so
`frontend-blue` stayed live throughout with zero user-facing impact -
confirmed live via `kubectl get endpoints frontend -n credpay`, which still
pointed at the blue pods' IPs.

**Root cause:** reproduced directly against the live pod with
`kubectl exec ... -- wget http://localhost:80/` (same failure), then
`kubectl exec ... -- wget http://127.0.0.1:80/` (succeeded) and
`getent hosts localhost` (resolved to `::1` first). The pod's
`/etc/hosts` maps `localhost` to both `127.0.0.1` and `::1`, but nginx's
`listen 80;` only binds `0.0.0.0:80` (confirmed via `ss -tlnp` inside the
pod — no `[::]:80` listener exists). BusyBox `wget` doesn't fall back
between address families, so resolving `localhost` to `::1` first gives an
immediate, correct-looking-but-wrong "Connection refused" against a
perfectly healthy container. `kubelet`'s own readiness/liveness probes were
unaffected because they connect to the pod IP directly, never through
"localhost".

**Fix:** changed the frontend's own smoke-test check from
`http://localhost:80/` to `http://127.0.0.1:80/` in both
`azure-pipelines.yml` and the manual command in `k8s/README.md`. The two
backend checks (`user-service`/`payment-service` cluster-DNS names) were
never affected - CoreDNS only returns IPv4 A records for those Services.

**Cleanup noted, not yet done:** the pre-blue/green `frontend` Deployment
and its `frontend` HPA (2 pods, running for 2 days before this session)
are now orphaned - they carry no `version` label, so the new `frontend`
Service selector (`app.kubernetes.io/name=frontend,version=blue`) never
matches them and they receive zero traffic. Safe to
`kubectl delete deployment frontend -n credpay && kubectl delete hpa frontend -n credpay`
once someone confirms nothing else depends on them.

---

## 3. Result

`terraform apply` completed successfully: **4 resources added** (the four
Key Vault secrets), 0 changed, 0 destroyed. Confirmed via the apply output:

```
aks_cluster_name       = "aks-credpay"
aks_resource_group     = "rg-credpay"
key_vault_name         = "kv-credpay"
postgres_fqdn          = "psql-credpay.postgres.database.azure.com"
postgres_server_name   = "psql-credpay"
postgres_admin_password = <sensitive>
```

The full `DeployToAKS` stage then ran end-to-end through the blue/green
rollout and correctly held traffic on `frontend-blue` when the smoke test
in §2.4 failed - proving the "don't switch on failure" safety behavior
works as designed on a live cluster, not just in theory. With the
`127.0.0.1` fix in place, the next pipeline run should get past the smoke
test and reach the traffic switch + final validation steps.
