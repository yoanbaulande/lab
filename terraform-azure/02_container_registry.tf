# Create an Azure Container Registry
resource "azurerm_container_registry" "acr" {
  name                = "acr${random_integer.suffix.result}"
  resource_group_name = azurerm_resource_group.cloud_rg.name
  location            = azurerm_resource_group.cloud_rg.location
  sku                 = "Basic"
  admin_enabled       = true
  depends_on          = [azurerm_resource_group.cloud_rg]
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}
