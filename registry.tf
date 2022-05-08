resource "azurerm_user_assigned_identity" "registry" {
  name                = "id-${local.resource_suffix}-cr"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_container_registry" "main" {
  name                   = "cr${var.project}${var.environment}${var.region}"
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  admin_enabled          = false
  anonymous_pull_enabled = false
  sku                    = "Premium"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.registry.id]
  }

  encryption = [{
    enabled            = true
    identity_client_id = azurerm_user_assigned_identity.registry.client_id
    key_vault_key_id   = azurerm_key_vault_key.main["registry"].id
  }]

  depends_on = [
    azurerm_role_assignment.disk_encryption_set_key_vault_crypto_service_encryption_user
  ]
}

resource "azurerm_private_endpoint" "registry" {
  name                = "pe-${local.resource_suffix}-cr"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_dns_zone_group {
    name                 = local.private_dns_zones.registry
    private_dns_zone_ids = [azurerm_private_dns_zone.main["registry"].id]
  }

  private_service_connection {
    name                           = azurerm_container_registry.main.name
    is_manual_connection           = false
    subresource_names              = ["registry"]
    private_connection_resource_id = azurerm_container_registry.main.id
  }
}
