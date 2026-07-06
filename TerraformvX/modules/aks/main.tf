resource "azurerm_kubernetes_cluster" "aks" {
  name = "${var.name_prefix}-aks-cluster"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
  dns_prefix          = "${var.name_prefix}-aks-dns"
  automatic_upgrade_channel = "stable"
  node_os_upgrade_channel = "NodeImage"
  role_based_access_control_enabled = true
  azure_policy_enabled              = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  local_account_disabled            = false
  node_resource_group = "${var.name_prefix}-aks-nodes"
    default_node_pool {
        name            = "${var.name_prefix}np"
        node_count      = var.aks_node_count
        vm_size         = var.aks_node_vm_size
        min_count       = var.minimum_node_count
        max_count       = var.maximum_node_count
        vnet_subnet_id  = var.aks_subnet_id
        os_sku = "Ubuntu"
        max_pods = 60
        type = "VirtualMachineScaleSets"
        auto_scaling_enabled = true
        upgrade_settings {
            max_surge = "70%"
        }

    }
    identity {
        type = "SystemAssigned"
    }
    network_profile {
        network_plugin = "azure"
        load_balancer_sku = "standard"
        outbound_type = "loadBalancer"
        service_cidr = "10.240.0.0/16"
        dns_service_ip = "10.240.0.1"
    }
    oms_agent {
        log_analytics_workspace_id = var.log_analytics_workspace_id
    }
}