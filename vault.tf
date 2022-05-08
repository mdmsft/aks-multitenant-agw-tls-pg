locals {
  keys = {
    cluster = {
      name         = "aks",
      principal_id = azurerm_user_assigned_identity.registry.principal_id
    },
    registry = {
      name         = "cr"
      principal_id = azurerm_user_assigned_identity.registry.principal_id
    }
  }
}

resource "azurerm_key_vault" "main" {
  name                       = substr("kv-${var.project}-${var.environment}-${var.region}", 0, 24)
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  enable_rbac_authorization  = true
  sku_name                   = "standard"
  tenant_id                  = var.tenant_id
  soft_delete_retention_days = var.key_vault_soft_delete_retention_days
  purge_protection_enabled   = true
}

resource "azurerm_role_assignment" "key_vault_administrator" {
  role_definition_name = "Key Vault Administrator"
  scope                = azurerm_key_vault.main.id
  principal_id         = data.azurerm_client_config.main.object_id
}

resource "azurerm_key_vault_certificate" "main" {
  name         = var.project
  key_vault_id = azurerm_key_vault.main.id

  certificate {
    contents = filebase64("./tls.pfx")
  }

  depends_on = [
    azurerm_role_assignment.key_vault_administrator
  ]
}

resource "azurerm_key_vault_key" "main" {
  for_each     = local.keys
  name         = each.key
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA"
  key_size     = 4096
  key_opts = [
    "decrypt",
    "encrypt",
    "sign",
    "unwrapKey",
    "verify",
    "wrapKey",
  ]

  depends_on = [
    azurerm_role_assignment.key_vault_administrator
  ]
}

resource "azurerm_key_vault_secret" "main" {
  for_each     = var.tenants
  name         = "${each.key}-postgres-connection-string"
  key_vault_id = azurerm_key_vault.main.id
  value        = "postgres://${var.postgres_administrator_login}:${var.postgres_administrator_password}@${azurerm_postgresql_flexible_server.main.name}.postgres.database.azure.com/postgres?sslmode=require"

  depends_on = [
    azurerm_role_assignment.key_vault_administrator
  ]
}

resource "azurerm_disk_encryption_set" "main" {
  for_each                  = local.keys
  name                      = "des-${local.resource_suffix}-${each.value.name}"
  location                  = azurerm_resource_group.main.location
  resource_group_name       = azurerm_resource_group.main.name
  auto_key_rotation_enabled = true
  key_vault_key_id          = azurerm_key_vault_key.main[each.key].id

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "disk_encryption_set_key_vault_crypto_user" {
  for_each             = local.keys
  role_definition_name = "Key Vault Crypto User"
  scope                = "/subscriptions/${data.azurerm_client_config.main.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.KeyVault/vaults/${azurerm_key_vault.main.name}/keys/${azurerm_key_vault_key.main[each.key].name}"
  principal_id         = azurerm_disk_encryption_set.main[each.key].identity[0].principal_id
}

resource "azurerm_role_assignment" "disk_encryption_set_key_vault_crypto_service_encryption_user" {
  for_each             = local.keys
  role_definition_name = "Key Vault Crypto Service Encryption User"
  scope                = "/subscriptions/${data.azurerm_client_config.main.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.KeyVault/vaults/${azurerm_key_vault.main.name}/keys/${azurerm_key_vault_key.main[each.key].name}"
  principal_id         = each.value.principal_id
}

resource "azurerm_role_assignment" "application_key_vault_secrets_user" {
  for_each             = var.tenants
  role_definition_name = "Key Vault Secrets User"
  scope                = "/subscriptions/${data.azurerm_client_config.main.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.KeyVault/vaults/${azurerm_key_vault.main.name}/secrets/${azurerm_key_vault_secret.main[each.key].name}"
  principal_id         = azuread_service_principal.main[each.key].object_id
}

resource "azurerm_role_assignment" "application_key_vault_secrets_user_certificate" {
  for_each             = var.tenants
  role_definition_name = "Key Vault Secrets User"
  scope                = "/subscriptions/${data.azurerm_client_config.main.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.KeyVault/vaults/${azurerm_key_vault.main.name}/secrets/${azurerm_key_vault_certificate.main.name}"
  principal_id         = azuread_service_principal.main[each.key].object_id
}

resource "azurerm_private_endpoint" "vault" {
  name                = "pe-${local.resource_suffix}-kv"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_dns_zone_group {
    name                 = local.private_dns_zones.vault
    private_dns_zone_ids = [azurerm_private_dns_zone.main["vault"].id]
  }

  private_service_connection {
    name                           = azurerm_key_vault.main.name
    is_manual_connection           = false
    subresource_names              = ["vault"]
    private_connection_resource_id = azurerm_key_vault.main.id
  }
}
