#Create a Kubernetes Cluster
locals {
  name_prefix = "credpay"
  tags = {
    environment = "dev"
    project     = "credpay"
  }

}

module "resource_group" {
  source              = "./modules/resource-group"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

module "vnet" {
  source                 = "./modules/virtual-network"
  name_prefix            = local.name_prefix
  location               = var.location
  resource_group_name    = module.resource_group.resource_group_name
  tags                   = local.tags
  address_space          = var.address_space
  aks_subnet_prefix      = var.aks_subnet_prefix
  postgres_subnet_prefix = var.postgres_subnet_prefix
}

module "monitoring" {
  source              = "./modules/monitoring"
  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = module.resource_group.resource_group_name
  tags                = local.tags
  log_rentention_days = var.log_rentention_days
}

module "postgres" {
  source              = "./modules/postgres"
  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = module.resource_group.resource_group_name
  tags                = local.tags
  postgres_version    = var.postgres_version
  post_admin_username = var.post_admin_username
  database_name       = var.database_name
  #postgres_subnet_prefix = module.vnet.postgres_subnet_prefix
}

module "aks" {
  source                     = "./modules/aks"
  name_prefix                = local.name_prefix
  location                   = var.location
  resource_group_name        = module.resource_group.resource_group_name
  tags                       = local.tags
  aks_node_count             = var.aks_node_count
  minimum_node_count         = var.minimum_node_count
  maximum_node_count         = var.maximum_node_count
  aks_node_vm_size           = var.aks_node_vm_size
  log_analytics_workspace_id = module.monitoring.workspace_id
  aks_subnet_id              = module.vnet.aks_subnet_id
}
