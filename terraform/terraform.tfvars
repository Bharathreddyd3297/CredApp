# =====================================================================
# CredPay - REAL variable values
# =====================================================================
# Intentionally committed for this classroom capstone project so the
# Azure DevOps pipeline's Terraform stage has subscription_id available
# (Azure DevOps secret pipeline variables can't be expanded into a task's
# `commandOptions` input, only into script env: mappings - see the
# azure-pipelines.yml history for why this file is committed instead).
# =====================================================================

# Azure Subscription ID
subscription_id = "eb2e4db4-1889-4351-9b48-102efd8a3a57"

# Azure Region
location = "canadacentral"

# ----- Networking -----
vnet_address_space     = "10.0.0.0/16"
aks_subnet_prefix      = "10.0.0.0/20"
postgres_subnet_prefix = "10.0.16.0/24"

# ----- AKS -----
node_count     = 3
node_min_count = 2
node_max_count = 5
vm_size        = "Standard_B2s"

# ----- PostgreSQL -----
postgres_version        = "16"
postgres_admin_username = "credpayadmin"
database_name           = "credpay"

# ----- Monitoring -----
log_retention_days = 30

# ----- Key Vault (created out-of-band, in the CredProj bootstrap RG - see backend.tf) -----
key_vault_name                = "kv-credpay"
key_vault_resource_group_name = "CredProj"
