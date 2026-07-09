# Can This Repo Be Shared So Others Can Run It On Their Own Azure Infra?

**Short answer: not yet, as-is.** There is one real **security** issue to fix
before sharing this repo with anyone outside your immediate, trusted team,
and a short list of values that are **hardcoded to your specific Azure
environment** and must change before someone else's `terraform apply` /
`kubectl apply` / pipeline run will succeed on their own subscription.

None of this is a flaw in the application itself — the app code
(frontend/backend) is already environment-agnostic after the Stage 1 fixes
(see `STAGE1-CHANGES.md`). This is entirely about infrastructure config that
is, by nature, specific to one deployment.

---

## A. Security issue — fix before sharing with anyone

### A.1 `terraform/terraform.tfvars` was committed to git with a real Azure Subscription ID

- The file's own header comment says `REAL variable values (git-ignored - do
  NOT commit)` — but `.gitignore`'s `*.tfvars` rule was commented out, so it
  was **not actually ignored**. It was committed on 2026-07-03 (commit
  `1dbfaab`, message "tfvars") and remained tracked until this session.
- It contains: `subscription_id = "eb2e4db4-1889-4351-9b48-102efd8a3a57"`.
- **Risk:** a subscription ID is not a login credential by itself, but Azure
  treats it as sensitive — it's the target for resource enumeration and
  reconnaissance, and standard practice is to never publish it, especially
  in a public repo.

**Fixed in this session:**
- `.gitignore` — uncommented the `*.tfvars` / `!*.tfvars.example` rules so
  this can't happen again.
- Ran `git rm --cached terraform/terraform.tfvars` — this **stages** the
  removal of the file from tracking. Your local file on disk is untouched
  (still has your real values, still usable for your own `terraform
  apply`), but the next commit will stop tracking it going forward.

**Not done — needs your decision:** the subscription ID **still exists in
git history** on commit `1dbfaab`, and will remain there even after the
change above is committed. If this repository is (or will become) public,
or if you're sharing the `.git` history itself (not just a fresh export),
that old commit still exposes the value. Purging it requires rewriting
history (`git filter-repo` or BFG Repo-Cleaner) and a force-push — a
destructive, collaboration-breaking operation I did not perform. Let me
know if you want help with that; it's most urgent if the GitHub repo is
public or about to be made public.

**Update (2026-07-09):** `terraform/terraform.tfvars` is now **intentionally
committed again**, subscription ID included. Root cause: Azure DevOps secret
pipeline variables can't be expanded into a `TerraformTask@5` `commandOptions`
input (only into script `env:` mappings), so passing `subscriptionId` as a
pipeline variable silently resolved to empty and broke `terraform apply` in
CI. The alternative fix (mark the pipeline variable non-secret) was offered
and explicitly declined in favor of committing the value, since this is a
classroom capstone project. If this repo is ever made public, revisit this
decision — the risk described above still applies.

---

## B. Hardcoded, environment-specific values — must change for someone else's Azure

Azure Storage Account names, PostgreSQL Flexible Server names, and ACR login
servers are all **globally unique across all of Azure**, not just within
your subscription. If someone else tries to reuse your exact names, their
deployment can fail outright with a "name already taken" error even if
they're in a completely different subscription.

| # | File | Current (yours) | Why it must change | What they do instead |
|---|------|------------------|---------------------|------------------------|
| 1 | `k8s/frontend/deployment-blue.yaml`, `k8s/frontend/deployment-green.yaml`, `k8s/user-service/deployment.yaml`, `k8s/payment-service/deployment.yaml` | `image: credproj.azurecr.io/credpay/...` | Points at *your* ACR | Create their own ACR, `az aks update --attach-acr <theirs>`, replace `credproj.azurecr.io` with `<theirs>.azurecr.io` in all 4 files |
| 2 | `k8s/configmap/configmap.yaml` | `DB_HOST` / `SPRING_DATASOURCE_URL` = `psql-credpay.postgres.database.azure.com` | Points at *your* Postgres server | After their own `terraform apply`, run `terraform output -raw postgres_fqdn` and substitute it in |
| 3 | `terraform/main.tf` line 7 | `name_prefix = "credpay"` (hardcoded `local`, not a `variable`) | Every resource name derives from this, including the globally-unique Postgres server name (`psql-credpay`). As long as your `psql-credpay` server exists, nobody else can create their own with the same prefix | They must edit this line to something unique (e.g. their name/team) before running `terraform apply` |
| 4 | `terraform/backend.tf` | `resource_group_name = "CredProj"`, `storage_account_name = "credprojstate"`, `container_name = "statefile"` | Points at *your* pre-existing remote-state storage account (storage account names are globally unique too). Terraform backend blocks cannot use variables, so this must be hand-edited | They provision their own state storage account (out-of-band, before `terraform init`) and edit this file to match |
| 5 | `azure-pipelines.yml` | `acrServiceConnection: 'CredPay-ACR-SC'`, `azureServiceConnection: 'scnew2'`, `tfStateRG/tfStateStorage/tfStateContainer/tfStateKey`, `keyVaultName`, `keyVaultResourceGroup` | These name *your* Azure DevOps service connections and *your* Key Vault, and must match whatever backend/vault they set up in #4 and #7 | They create their own Azure DevOps service connections and Key Vault, and update these pipeline variables |
| 6 | `terraform/terraform.tfvars` | `subscription_id = "eb2e4db4-..."`, `key_vault_name = "kv-credpay"`, `key_vault_resource_group_name = "CredProj"` | Points at *your* subscription and *your* Key Vault (also globally unique) - see the 2026-07-09 update in section A above for why this file is committed at all | Create their own Key Vault, grant Terraform's identity `Key Vault Secrets Officer` on it, and set all three values to match their own subscription/vault |
| 7 | `k8s/README.md`, `terraform/README.md` (docs only) | Mentions of `credproj.azurecr.io`, `az aks update --attach-acr credproj`, `kv-credpay` | Cosmetic, but misleading once 1–6 are changed | Update after the above so the runbooks stay accurate |

**Already parameterized correctly — no change needed:** `postgres_admin_username`,
`database_name`, `postgres_version`, `node_count`/`node_min_count`/`node_max_count`,
`vm_size`, `location`, `vnet_address_space`, and subnet prefixes are all real
Terraform `variable`s with sane defaults in `terraform.tfvars.example`. Anyone
reusing this repo just copies that file to `terraform.tfvars` and fills in
their own `subscription_id` and `location`.

---

## C. Not blockers, but worth cleaning up before sharing

- **`TerraformvX/`** — an earlier, superseded draft of the Terraform code
  (different module names/layout, e.g. `virtual-network` instead of
  `networking`, no `outputs.tf` producing `postgres_fqdn` etc.). Nothing
  references it — `azure-pipelines.yml` points at `workingDirectory:
  terraform`, not `TerraformvX`. It's dead weight that will confuse anyone
  reading the repo fresh. Safe to delete.
- **`TerraformvX/terraform zip.zip`** — an 8.8 KB zip of `.tf` source files
  checked into git. I inspected its contents directly: only `.tf` files, no
  state file, no credentials. Still just clutter — recommend deleting.
- Give the rest of the repo (`Order.docx`, `PROJECT_TRACKER.md`, etc.) a
  quick skim before making the repo public, in case anything in there was
  meant to stay internal — I did not open these, since they're outside the
  infra/portability scope of this review.

---

## D. Already portable — confirmed, no change needed

- **Frontend/backend application code** — driven entirely by relative URLs
  and environment variables / ConfigMap+Secret (Stage 1 work). Same image
  works behind any Ingress IP.
- **Kubernetes manifest structure** — names, selectors, labels, probes,
  resource limits, HPAs are all reusable as-is once the values in §B are
  updated for the new environment.
- **Terraform module code** (`modules/aks`, `modules/postgres`,
  `modules/networking`, `modules/monitoring`, `modules/resource-group`) —
  correctly parameterized; `tenant_id` is read dynamically via
  `data.azurerm_client_config.current`, never hardcoded.

---

## Suggested runbook for handing this to someone else

1. Decide whether the current GitHub repo can remain the shared copy given
   the tfvars history exposure (§A), or whether to scrub history / start a
   fresh repo first.
2. Give them: repo access, plus this sequence:
   - Fork/clone the repo.
   - Create their own ACR and their own Terraform remote-state storage
     account (both need globally-unique names).
   - Copy `terraform/terraform.tfvars.example` → `terraform.tfvars`, fill in
     their `subscription_id` and `location`.
   - Edit `terraform/main.tf` line 7 (`name_prefix`) to something unique to
     them.
   - Edit `terraform/backend.tf` to point at their state storage account.
   - `terraform apply`.
   - `az aks update --attach-acr <their-acr-name>`.
   - Get `terraform output -raw postgres_fqdn` and their ACR login server;
     update `k8s/configmap/configmap.yaml` and the `image:` line in all
     three Deployments (§B, rows 1–2).
   - Create an Azure DevOps project + service connections pointing at
     *their* subscription/ACR; update the pipeline variables (§B, row 5).
   - Push, let the pipeline build/push images, then follow
     `STAGE1-CHANGES.md` §5 for the manual `kubectl apply` deployment steps.

---

## What was actually changed in this session

| File | Change |
|---|---|
| `.gitignore` | Uncommented the `*.tfvars` / `!*.tfvars.example` exclusion rules. |
| `terraform/terraform.tfvars` | Untracked from git via `git rm --cached` (staged, not committed). The file still exists locally with your real values. |

Nothing else was modified — no Terraform resource names, no pipeline
variables, no Kubernetes manifests were changed as part of this review,
since those are decisions only you (or whoever you hand this to) can make
for their own environment. This file is the checklist for that; I did not
apply §B's changes since they'd need real values for a *different*
environment that doesn't exist yet.
