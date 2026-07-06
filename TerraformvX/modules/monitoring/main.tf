#Monitoring module
resource "azurerm_log_analytics_workspace" "log_analytics" {
  name                = "${var.name_prefix}-log-analytics"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_rentention_days
  tags                = var.tags
}

#For Container insights monitoring, we need to create a Log Analytics solution in the workspace
resource "azurerm_log_analytics_solution" "container_insights_solution" {
  solution_name         = "${var.name_prefix}-log-analytics-solution"
  location              = var.location
  resource_group_name   = var.resource_group_name
  workspace_resource_id = azurerm_log_analytics_workspace.log_analytics.id
  workspace_name        = azurerm_log_analytics_workspace.log_analytics.name
  plan {
    product       = "OMSGallery/ContainerInsights"
    publisher     = "Microsoft"
  }
  tags = var.tags
}