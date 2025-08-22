resource "azapi_resource" "aks_automatic" {
  count                     = var.deploy_automatic ? 1 : 0
  name                      = "${var.aks_automatic_name}-${random_string.cluster_name_suffix.result}"
  location                  = var.location
  parent_id                 = azurerm_resource_group.aks_rg.id
  // Using latest AKS Managed Cluster API version (see variables.tf: aks_api_version)
  type                      = "Microsoft.ContainerService/managedClusters@${var.aks_api_version}"
  schema_validation_enabled = false
  response_export_values    = ["*"] // Export all values from the response, including identity information

  body = jsonencode({
    properties = {
      dnsPrefix = "${var.aks_automatic_name}-dns-${random_string.cluster_name_suffix.result}"
      kubernetesVersion = var.kubernetes_version
      enableRBAC = true
      agentPoolProfiles = [
        {
          name = "system"
          count = var.system_node_count
          vmSize = var.sku
          mode = "System"
          orchestratorVersion = var.kubernetes_version
          availabilityZones = [for z in var.zones : tostring(z)]
        },
        {
          name = "user"
          count = var.user_node_count
          vmSize = var.sku
          mode = "User"
          availabilityZones = [for z in var.zones : tostring(z)]
        }
      ],
      # Add Azure Policy configuration
      addonProfiles = {
        azurepolicy = {
          enabled = true
        },
        # Add Azure Monitor configuration
        omsagent = {
          enabled = true,
          config = {
            logAnalyticsWorkspaceResourceID = azurerm_log_analytics_workspace.aks.id
          }
        }
      },
      # Add AAD integration with Azure RBAC enabled
      aadProfile = {
        managed = true,
        adminGroupObjectIDs = [var.aad_admin_group_object_id],
        tenantID = var.aad_tenant_id,
        enableAzureRBAC = true
      },
      networkProfile = merge(
        {
          networkDataplane = var.enable_advanced_networking ? "cilium" : null
        },
        var.enable_advanced_networking ? {
          advancedNetworking = {
            enabled = true
            observability = { enabled = true }
            security       = { enabled = true }
          }
        } : {}
      )
    }
    identity = {
      type = "SystemAssigned"
    }
    sku = {
      name = "Automatic"
      tier = "Standard"
    }
  })
}

// Secondary Automatic cluster without advanced networking
resource "azapi_resource" "aks_automatic_basic" {
  count                     = var.deploy_automatic_basic ? 1 : 0
  name                      = "${var.aks_automatic_basic_name}-${random_string.cluster_name_suffix.result}"
  location                  = var.location
  parent_id                 = azurerm_resource_group.aks_rg.id
  type                      = "Microsoft.ContainerService/managedClusters@${var.aks_api_version}"
  schema_validation_enabled = false
  response_export_values    = ["*"]

  body = jsonencode({
    properties = {
      dnsPrefix         = "${var.aks_automatic_basic_name}-dns-${random_string.cluster_name_suffix.result}"
      kubernetesVersion = var.kubernetes_version
      enableRBAC        = true
      agentPoolProfiles = [
        {
          name                = "system"
          count               = var.system_node_count
          vmSize              = var.sku
          mode                = "System"
          orchestratorVersion = var.kubernetes_version
          availabilityZones   = [for z in var.zones : tostring(z)]
        },
        {
          name                = "user"
          count               = var.user_node_count
          vmSize              = var.sku
          mode                = "User"
          availabilityZones   = [for z in var.zones : tostring(z)]
        }
      ]
      addonProfiles = {
        azurepolicy = { enabled = true }
        omsagent    = { enabled = true, config = { logAnalyticsWorkspaceResourceID = azurerm_log_analytics_workspace.aks.id } }
      }
      aadProfile = {
        managed              = true
        adminGroupObjectIDs  = [var.aad_admin_group_object_id]
        tenantID             = var.aad_tenant_id
        enableAzureRBAC      = true
      }
      // No advancedNetworking block here
    }
    identity = { type = "SystemAssigned" }
    sku      = { name = "Automatic", tier = "Standard" }
  })
}
