resource "azurerm_virtual_network" "vnet" {
  name                = "${var.name_prefix}-vnet"
  address_space       = [var.address_space]
  location            = var.location
  tags                = var.tags
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "aks_subnet" {
  name                = "${var.name_prefix}-aks-subnet"
  address_prefixes    = [var.aks_subnet_prefix]
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "postgres_subnet" {
  name                = "${var.name_prefix}-postgres-subnet"
  address_prefixes    = [var.postgres_subnet_prefix]
  virtual_network_name = azurerm_virtual_network.vnet.name
  resource_group_name = var.resource_group_name
}
