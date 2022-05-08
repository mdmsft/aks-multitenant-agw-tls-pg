resource "azurerm_postgresql_flexible_server" "main" {
  name                         = "psql-${local.resource_suffix}"
  resource_group_name          = azurerm_resource_group.main.name
  location                     = azurerm_resource_group.main.location
  version                      = var.postgres_version
  delegated_subnet_id          = azurerm_subnet.postgres.id
  private_dns_zone_id          = azurerm_private_dns_zone.main["postgres"].id
  administrator_login          = var.postgres_administrator_login
  administrator_password       = var.postgres_administrator_password
  backup_retention_days        = var.postgres_backup_retention_days
  geo_redundant_backup_enabled = var.postgres_geo_redundant_backup_enabled
  sku_name                     = var.postgres_sku_name
  storage_mb                   = var.postgres_storage_mb

  high_availability {
    mode = "ZoneRedundant"
  }

  lifecycle {
    ignore_changes = [
      zone,
      high_availability.0.standby_availability_zone
    ]
  }

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.main
  ]
}

resource "azurerm_postgresql_flexible_server_database" "main" {
  for_each  = var.tenants
  name      = each.value
  server_id = azurerm_postgresql_flexible_server.main.id
}
