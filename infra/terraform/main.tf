# Resource Group
resource "azurerm_resource_group" "main" {
  name     = "${local.resource_prefix}-rg"
  location = var.location
  tags     = local.tags
}

# Storage Account (FREE TIER: 5GB blob, queue, table)
resource "azurerm_storage_account" "main" {
  name                            = replace("${local.resource_prefix}stor", "-", "")
  resource_group_name             = azurerm_resource_group.main.name
  location                        = azurerm_resource_group.main.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = true  # Required for Functions
  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = local.tags
}

# Storage Queue for work items
resource "azurerm_storage_queue" "work" {
  name                 = "molten-work"
  storage_account_name = azurerm_storage_account.main.name
}

# Storage Container for configs/sessions
resource "azurerm_storage_container" "configs" {
  name                  = "molten-configs"
  storage_account_name  = azurerm_storage_account.main.name
  container_access_type = "private"
}

# Key Vault for secrets
resource "azurerm_key_vault" "main" {
  name                       = "${local.resource_prefix}-kv"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = 7
  purge_protection_enabled   = false # Set true for production

  enable_rbac_authorization = true

  network_acls {
    default_action = var.keyvault_network_default_action # "Deny" for production
    bypass         = "AzureServices"
  }

  tags = local.tags
}

data "azurerm_client_config" "current" {}

# Grant deploying user access to Key Vault secrets
resource "azurerm_role_assignment" "deployer_kv" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Store secrets in Key Vault
resource "azurerm_key_vault_secret" "aoai_endpoint" {
  name         = "azure-openai-endpoint"
  value        = var.azure_openai_endpoint
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer_kv]
}

resource "azurerm_key_vault_secret" "aoai_key" {
  name         = "azure-openai-api-key"
  value        = var.azure_openai_api_key
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer_kv]
}

resource "azurerm_key_vault_secret" "telegram_token" {
  count        = var.telegram_bot_token != "" ? 1 : 0
  name         = "telegram-bot-token"
  value        = var.telegram_bot_token
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer_kv]
}

# Log Analytics Workspace (FREE: 5GB/month)
resource "azurerm_log_analytics_workspace" "main" {
  name                = "${local.resource_prefix}-logs"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = local.tags
}

# Application Insights
resource "azurerm_application_insights" "main" {
  name                = "${local.resource_prefix}-insights"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "Node.JS"

  tags = local.tags
}

# Azure Functions - Service Plan (Consumption tier for free tier)
resource "azurerm_service_plan" "functions" {
  name                = "${local.resource_prefix}-func-plan"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption tier - FREE: 1M executions/month
  tags                = local.tags
}

resource "azurerm_linux_function_app" "main" {
  name                       = "${local.resource_prefix}-func"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  service_plan_id            = azurerm_service_plan.functions.id
  storage_account_name       = azurerm_storage_account.main.name
  storage_account_access_key = azurerm_storage_account.main.primary_access_key

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      node_version = "20"
    }

    application_insights_key               = azurerm_application_insights.main.instrumentation_key
    application_insights_connection_string = azurerm_application_insights.main.connection_string
  }

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME" = "node"
    "QUEUE_NAME"               = azurerm_storage_queue.work.name
    "KEY_VAULT_URI"            = azurerm_key_vault.main.vault_uri
    "STORAGE_ACCOUNT_NAME"     = azurerm_storage_account.main.name
    "AzureWebJobsStorage"      = azurerm_storage_account.main.primary_connection_string
  }

  tags = local.tags
}

# Grant Functions access to Key Vault
resource "azurerm_role_assignment" "func_kv" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Functions access to Storage Queue
resource "azurerm_role_assignment" "func_queue" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Container Registry - DISABLED: Using GitHub Container Registry instead for cost savings
# Basic SKU costs ~$5/month, GHCR is free for public repos
# resource "random_string" "acr_suffix" {
#   length  = 6
#   special = false
#   upper   = false
# }

# resource "azurerm_container_registry" "main" {
#   name                = "${replace(local.resource_prefix, "-", "")}acr${random_string.acr_suffix.result}"
#   resource_group_name = azurerm_resource_group.main.name
#   location            = azurerm_resource_group.main.location
#   sku                 = "Basic"
#   admin_enabled       = true
#
#   tags = local.tags
# }

# Container Apps - DISABLED: Using Azure Functions for webhook handling
# Kept for reference in case Container Apps is needed for heavier workloads
# resource "azurerm_container_app_environment" "main" {
#   name                       = "${local.resource_prefix}-cae"
#   location                   = azurerm_resource_group.main.location
#   resource_group_name        = azurerm_resource_group.main.name
#   log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
#
#   tags = local.tags
# }

# Container App Agent - DISABLED: Using Azure Functions instead
# resource "azurerm_container_app" "agent" {
#   name                         = "${local.resource_prefix}-agent"
#   container_app_environment_id = azurerm_container_app_environment.main.id
#   resource_group_name          = azurerm_resource_group.main.name
#   revision_mode                = "Single"
#
#   identity {
#     type = "SystemAssigned"
#   }
#
#   registry {
#     server               = azurerm_container_registry.main.login_server
#     username             = azurerm_container_registry.main.admin_username
#     password_secret_name = "acr-password"
#   }
#
#   secret {
#     name  = "acr-password"
#     value = azurerm_container_registry.main.admin_password
#   }
#
#   template {
#     min_replicas = 0 # Scale to zero when idle!
#     max_replicas = 2
#
#     container {
#       name   = "agent"
#       image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
#       cpu    = 0.25
#       memory = "0.5Gi"
#
#       env {
#         name  = "AZURE_OPENAI_ENDPOINT"
#         value = var.azure_openai_endpoint
#       }
#       env {
#         name  = "AZURE_OPENAI_DEPLOYMENT"
#         value = var.azure_openai_deployment
#       }
#       env {
#         name        = "AZURE_OPENAI_API_KEY"
#         secret_name = "aoai-key"
#       }
#       env {
#         name  = "STORAGE_ACCOUNT_NAME"
#         value = azurerm_storage_account.main.name
#       }
#       env {
#         name  = "QUEUE_NAME"
#         value = azurerm_storage_queue.work.name
#       }
#       env {
#         name  = "KEY_VAULT_URI"
#         value = azurerm_key_vault.main.vault_uri
#       }
#     }
#   }
#
#   secret {
#     name  = "aoai-key"
#     value = var.azure_openai_api_key
#   }
#
#   ingress {
#     external_enabled = true
#     target_port      = 8080
#     transport        = "http"
#
#     traffic_weight {
#       percentage      = 100
#       latest_revision = true
#     }
#   }
#
#   tags = local.tags
# }

# Container App role assignments - DISABLED
# resource "azurerm_role_assignment" "agent_kv" {
#   scope                = azurerm_key_vault.main.id
#   role_definition_name = "Key Vault Secrets User"
#   principal_id         = azurerm_container_app.agent.identity[0].principal_id
# }

# resource "azurerm_role_assignment" "agent_storage" {
#   scope                = azurerm_storage_account.main.id
#   role_definition_name = "Storage Blob Data Contributor"
#   principal_id         = azurerm_container_app.agent.identity[0].principal_id
# }

# resource "azurerm_role_assignment" "agent_queue" {
#   scope                = azurerm_storage_account.main.id
#   role_definition_name = "Storage Queue Data Contributor"
#   principal_id         = azurerm_container_app.agent.identity[0].principal_id
# }
