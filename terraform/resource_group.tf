resource "azurerm_resource_group" "aks_rg" {
  name     = "${var.resource_group_name}-${random_string.cluster_name_suffix.result}"
  location = var.location
}

resource "random_string" "cluster_name_suffix" {
  length  = 6
  special = false
  upper   = false
}
