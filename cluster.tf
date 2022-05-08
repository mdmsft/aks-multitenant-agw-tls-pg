locals {
  subnets = [
    azurerm_subnet.cluster_system_node_pool.id,
    azurerm_subnet.cluster_user_node_pool.id,
    azurerm_subnet.cluster_services.id
  ]
}

resource "azurerm_kubernetes_cluster" "main" {
  name                              = "aks-${local.context_name}"
  location                          = azurerm_resource_group.main.location
  resource_group_name               = azurerm_resource_group.main.name
  dns_prefix                        = local.context_name
  automatic_channel_upgrade         = var.kubernetes_cluster_automatic_channel_upgrade
  role_based_access_control_enabled = true
  disk_encryption_set_id            = azurerm_disk_encryption_set.main["cluster"].id
  azure_policy_enabled              = var.kubernetes_cluster_azure_policy_enabled
  kubernetes_version                = var.kubernetes_cluster_orchestrator_version
  local_account_disabled            = true
  oidc_issuer_enabled               = true
  node_resource_group               = "rg-${local.resource_suffix}-aks"
  sku_tier                          = var.kubernetes_cluster_sku_tier

  azure_active_directory_role_based_access_control {
    managed            = true
    azure_rbac_enabled = true
  }

  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.kubernetes_cluster_default_node_pool_vm_size
    enable_auto_scaling          = true
    min_count                    = var.kubernetes_cluster_default_node_pool_min_count
    max_count                    = var.kubernetes_cluster_default_node_pool_max_count
    max_pods                     = var.kubernetes_cluster_default_node_pool_max_pods
    os_disk_size_gb              = var.kubernetes_cluster_default_node_pool_os_disk_size_gb
    os_disk_type                 = var.kubernetes_cluster_default_node_pool_os_disk_type
    os_sku                       = var.kubernetes_cluster_default_node_pool_os_sku
    orchestrator_version         = var.kubernetes_cluster_default_node_pool_orchestrator_version == null ? var.kubernetes_cluster_orchestrator_version : var.kubernetes_cluster_default_node_pool_orchestrator_version
    only_critical_addons_enabled = true
    vnet_subnet_id               = azurerm_subnet.cluster_system_node_pool.id
    zones                        = var.kubernetes_cluster_default_node_pool_availability_zones

    upgrade_settings {
      max_surge = var.kubernetes_cluster_default_node_pool_max_surge
    }
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = var.kubernetes_cluster_network_policy
    dns_service_ip     = cidrhost(var.kubernetes_cluster_service_cidr, 10)
    docker_bridge_cidr = var.kubernetes_cluster_docker_bridge_cidr
    service_cidr       = var.kubernetes_cluster_service_cidr
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "1m"
  }

  microsoft_defender {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  depends_on = [
    azurerm_role_assignment.disk_encryption_set_key_vault_crypto_service_encryption_user
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "main" {
  name                  = "workload"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = var.kubernetes_cluster_workload_node_pool_vm_size
  enable_auto_scaling   = true
  min_count             = var.kubernetes_cluster_workload_node_pool_min_count
  max_count             = var.kubernetes_cluster_workload_node_pool_max_count
  max_pods              = var.kubernetes_cluster_workload_node_pool_max_pods
  os_disk_size_gb       = var.kubernetes_cluster_workload_node_pool_os_disk_size_gb
  os_disk_type          = var.kubernetes_cluster_workload_node_pool_os_disk_type
  os_sku                = var.kubernetes_cluster_workload_node_pool_os_sku
  orchestrator_version  = var.kubernetes_cluster_workload_node_pool_orchestrator_version == null ? var.kubernetes_cluster_orchestrator_version : var.kubernetes_cluster_workload_node_pool_orchestrator_version
  vnet_subnet_id        = azurerm_subnet.cluster_user_node_pool.id
  zones                 = var.kubernetes_cluster_workload_node_pool_availability_zones
  node_labels           = var.kubernetes_cluster_workload_node_pool_labels
  node_taints           = var.kubernetes_cluster_workload_node_pool_taints

  upgrade_settings {
    max_surge = var.kubernetes_cluster_workload_node_pool_max_surge
  }
}

resource "azurerm_role_assignment" "client_cluster_admin" {
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  scope                = azurerm_kubernetes_cluster.main.id
  principal_id         = data.azurerm_client_config.main.object_id
}

resource "azurerm_role_assignment" "cluster_network_contributor" {
  count                = length(local.subnets)
  role_definition_name = "Network Contributor"
  scope                = local.subnets[count.index]
  principal_id         = azurerm_kubernetes_cluster.main.identity.0.principal_id
}

resource "azurerm_role_assignment" "secrets_provider_key_vault_secrets_user" {
  for_each             = toset(var.tenants)
  role_definition_name = "Key Vault Secrets User"
  scope                = "/subscriptions/${data.azurerm_client_config.main.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.KeyVault/vaults/${azurerm_key_vault.main.name}/secrets/${azurerm_key_vault_secret.main[each.key].name}"
  principal_id         = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].object_id
}

resource "azurerm_role_assignment" "secrets_provider_key_vault_certificates_officer" {
  role_definition_name = "Key Vault Certificates Officer"
  scope                = "/subscriptions/${data.azurerm_client_config.main.subscription_id}/resourceGroups/${azurerm_resource_group.main.name}/providers/Microsoft.KeyVault/vaults/${azurerm_key_vault.main.name}/certificates/${azurerm_key_vault_certificate.main.name}"
  principal_id         = azurerm_kubernetes_cluster.main.key_vault_secrets_provider[0].secret_identity[0].object_id
}

resource "azurerm_role_assignment" "registry_pull" {
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.main.id
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
