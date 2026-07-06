resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_postgresql_flexible_server" "postgres" {
  name                = "${var.name_prefix}-postgres"
  location            = var.location
  resource_group_name = var.resource_group_name
  version             = var.postgres_version
  administrator_login = var.post_admin_username
  administrator_password = random_password.admin.result
  sku_name            = "B_Standard_B2s"
  storage_mb          = 32768
  backup_retention_days = 7
  auto_grow_enabled   = true
  public_network_access_enabled = true
  tags                = var.tags  
}

resource "azurerm_postgresql_flexible_server_database" "credpay_db" {
    name = var.database_name
    server_id = azurerm_postgresql_flexible_server.postgres.id
    charset   = "UTF8" #Supports wide range of characters. If not, only english should be used
    collation = "en_US.utf8" #How the data is sorted inside the database
}

resource "azurerm_postgresql_flexible_server_configuration" "name" {
  name      = "require_secure_transport"
  server_id = azurerm_postgresql_flexible_server.postgres.id
  value     = "ON"
}

resource "azurerm_postgresql_flexible_server_firewall_rule" "ssl" {
    name      = "ssl"
    server_id = azurerm_postgresql_flexible_server.postgres.id
    start_ip_address = "0.0.0.0"
    end_ip_address = "0.0.0.0"
}