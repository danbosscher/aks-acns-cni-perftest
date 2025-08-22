output "automatic_aks_id" {
  description = "The resource ID of the automatic AKS cluster"
  value       = var.deploy_automatic ? azapi_resource.aks_automatic[0].id : null
}

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.aks_rg.name
}

output "automatic_aks_name" {
  description = "The name of the automatic AKS cluster"
  value       = var.deploy_automatic ? var.aks_automatic_name : null
}
