output "aks_subnet_id" {
  description = "The ID of the AKS subnet."
  value       = azurerm_subnet.aks_subnet.id
}