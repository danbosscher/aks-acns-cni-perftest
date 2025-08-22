resource "random_string" "acr_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_container_registry" "acr" {
  name                = "${var.acr_name}${random_string.acr_suffix.result}"
  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = azurerm_resource_group.aks_rg.location
  sku                 = "Standard"
  admin_enabled       = true
}

resource "azurerm_role_assignment" "aks_automatic_to_acr" {
  count                = var.deploy_automatic ? 1 : 0
  principal_id         = jsondecode(azapi_resource.aks_automatic[0].output).properties.identityProfile.kubeletidentity.objectId
  role_definition_name = "AcrPull"
  scope                = azurerm_container_registry.acr.id
}

# Output the ACR login server
output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

# Output ACR admin username and password
output "acr_admin_username" {
  value = azurerm_container_registry.acr.admin_username
}

output "acr_admin_password" {
  value     = azurerm_container_registry.acr.admin_password
  sensitive = true
}