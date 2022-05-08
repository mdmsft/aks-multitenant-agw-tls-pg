resource "azuread_application" "main" {
  for_each     = var.tenants
  display_name = "app-${local.resource_suffix}-${each.key}"
  owners       = [data.azuread_client_config.main.object_id]
}

resource "azuread_service_principal" "main" {
  for_each                     = var.tenants
  application_id               = azuread_application.main[each.key].application_id
  owners                       = [data.azuread_client_config.main.object_id]
  app_role_assignment_required = false
}

resource "azuread_application_federated_identity_credential" "main" {
  for_each              = var.tenants
  application_object_id = azuread_application.main[each.key].id
  display_name          = "aks-${each.key}"
  audiences             = ["api://AzureADTokenExchange"]
  issuer                = azurerm_kubernetes_cluster.main.oidc_issuer_url
  subject               = "system:serviceaccount:${each.key}:default"
}
