output "azurerm_log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.log_analytics.name
  
}

output "workspace_id" {
  value = azurerm_log_analytics_workspace.log_analytics.id
}