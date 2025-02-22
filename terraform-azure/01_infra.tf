# Create a resource group
resource "azurerm_resource_group" "cloud_rg" {
  name     = "Projet_Cloud_${random_integer.suffix.result}-${var.environment}"
  location = "West Europe"
}

resource "random_integer" "suffix" {
  min = 10000000
  max = 99999999
}

resource "azurerm_storage_account" "storage_account" {
  name                     = "sa${random_integer.suffix.result}"
  resource_group_name      = azurerm_resource_group.cloud_rg.name
  location                 = azurerm_resource_group.cloud_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "storage_container" {
  name                  = "sg${random_integer.suffix.result}"
  storage_account_id    = azurerm_storage_account.storage_account.id
  container_access_type = "private"
}

resource "azurerm_storage_blob" "storage_blob" {
  name                   = "function_app.zip"
  storage_account_name   = azurerm_storage_account.storage_account.name
  storage_container_name = azurerm_storage_container.storage_container.name
  type                   = "Block"
  source                 = var.source_zip
}

data "azurerm_storage_account_sas" "storage_account_sas" {
  connection_string = azurerm_storage_account.storage_account.primary_connection_string
  start             = "2024-01-01"
  expiry            = "2025-12-31"
  resource_types {
    service   = true
    container = true
    object    = true
  }
  services {
    blob  = true
    queue = false
    table = false
    file  = false
  }
  permissions {
    read    = true
    write   = false
    delete  = false
    list    = false
    add     = false
    create  = false
    update  = false
    process = false
    tag     = false
    filter  = false
  }
}

resource "azurerm_log_analytics_workspace" "log_workspace" {
  name                = "laws${random_integer.suffix.result}"
  location            = azurerm_resource_group.cloud_rg.location
  resource_group_name = azurerm_resource_group.cloud_rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_service_plan" "back_plan" {
  name                = "bp${random_integer.suffix.result}"
  resource_group_name = azurerm_resource_group.cloud_rg.name
  location            = azurerm_resource_group.cloud_rg.location
  sku_name            = "B1"
  os_type             = "Linux"
}

resource "azurerm_application_insights" "app_insights" {
  name                = "ai${random_integer.suffix.result}"
  location            = azurerm_resource_group.cloud_rg.location
  resource_group_name = azurerm_resource_group.cloud_rg.name
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.log_workspace.id
}

resource "azurerm_linux_function_app" "function_app" {
  name                = "fa${random_integer.suffix.result}"
  location            = azurerm_resource_group.cloud_rg.location
  resource_group_name = azurerm_resource_group.cloud_rg.name
  service_plan_id     = azurerm_service_plan.back_plan.id

  storage_account_name       = azurerm_storage_account.storage_account.name
  storage_account_access_key = azurerm_storage_account.storage_account.primary_access_key

  site_config {
    application_stack {
      python_version = "3.11"
    }
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"       = "python"
    "WEBSITE_RUN_FROM_PACKAGE"       = "https://${azurerm_storage_account.storage_account.name}.blob.core.windows.net/${azurerm_storage_container.storage_container.name}/${azurerm_storage_blob.storage_blob.name}?${data.azurerm_storage_account_sas.storage_account_sas.sas}"
    "APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.app_insights.instrumentation_key
  }
}

resource "azurerm_container_group" "container_instance" {
  count               = var.deploy_registry ? 0 : 1
  name                = "aci${random_integer.suffix.result}"
  location            = azurerm_resource_group.cloud_rg.location
  resource_group_name = azurerm_resource_group.cloud_rg.name
  ip_address_type     = "Public"
  dns_name_label      = "aci-${random_integer.suffix.result}"
  exposed_port = [
    {
      protocol = "TCP"
      port     = 80
    }
  ]
  os_type = "Linux"

  container {
    name   = "frontend"
    image  = "${azurerm_container_registry.acr.name}.azurecr.io/front-end:0.0.3"
    cpu    = "0.5"
    memory = "1.5"

    ports {
      port     = 80
      protocol = "TCP"
    }

    environment_variables = {
      APP_INSIGHT_INSTRUMENTATION_KEY = azurerm_application_insights.app_insights.instrumentation_key
      APP_CONFIG_CONNECTION_STRING    = azurerm_app_configuration.app_config.primary_read_key[0].connection_string
    }
  }

  image_registry_credential {
    server   = azurerm_container_registry.acr.login_server
    username = azurerm_container_registry.acr.admin_username
    password = azurerm_container_registry.acr.admin_password
  }


  tags = {
    environment = "testing"
  }
}

data "azurerm_function_app_host_keys" "function_keys" {
  name                = azurerm_linux_function_app.function_app.name
  resource_group_name = azurerm_resource_group.cloud_rg.name
}

resource "azurerm_api_management" "apiman" {
  name                = "apiman${random_integer.suffix.result}"
  location            = azurerm_resource_group.cloud_rg.location
  resource_group_name = azurerm_resource_group.cloud_rg.name
  publisher_name      = "Projet Cloud 2"
  publisher_email     = "yoan.baulande@protonmail.com"

  sku_name = "Developer_1"
}

resource "azurerm_api_management_api" "ama" {
  name                  = "ama${random_integer.suffix.result}"
  resource_group_name   = azurerm_resource_group.cloud_rg.name
  api_management_name   = azurerm_api_management.apiman.name
  revision              = "1"
  display_name          = "API Management API"
  path                  = "api"
  protocols             = ["https"]
  subscription_required = false
  import {
    content_format = "openapi+json"
    content_value  = file("../back/swagger.json")
  }
  service_url = "https://${azurerm_linux_function_app.function_app.default_hostname}/api"
}

resource "azurerm_api_management_api_policy" "ama_policy" {
  api_management_name = azurerm_api_management.apiman.name
  api_name            = azurerm_api_management_api.ama.name
  resource_group_name = azurerm_resource_group.cloud_rg.name
  xml_content         = <<XML
<policies>
    <inbound>
        <base />
        <set-query-parameter name="code" exists-action="override">
            <value>${data.azurerm_function_app_host_keys.function_keys.default_function_key}</value>
        </set-query-parameter>
    </inbound>
    <backend>
        <base />
    </backend>
    <outbound>
        <base />
    </outbound>
    <on-error>
        <base />
    </on-error>
</policies>
XML
}

resource "azurerm_app_configuration" "app_config" {
  name                = "ac${random_integer.suffix.result}"
  resource_group_name = azurerm_resource_group.cloud_rg.name
  location            = azurerm_resource_group.cloud_rg.location
  sku                 = "standard"
}

data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "appconf_dataowner" {
  scope                = azurerm_app_configuration.app_config.id
  role_definition_name = "App Configuration Data Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_app_configuration_key" "api_url" {
  configuration_store_id = azurerm_app_configuration.app_config.id
  key                    = "ApiManagementUrl"
  value                  = azurerm_api_management.apiman.gateway_url
  depends_on = [
    azurerm_role_assignment.appconf_dataowner
  ]
}

output "api_url" {
  value = "${azurerm_api_management.apiman.gateway_url}/${azurerm_api_management_api.ama.path}"
}

output "front_url" {
  value = azurerm_container_group.container_instance[0].fqdn
}
