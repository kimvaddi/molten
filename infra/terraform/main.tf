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
  shared_access_key_enabled       = true # Required for Functions initial deployment
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true # Prefer Azure AD authentication

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  # Network security: Allow access for dev (no private endpoints)
  # For production, use "Deny" with private endpoints or VNet integration
  public_network_access_enabled = true
  network_rules {
    default_action             = "Allow"
    bypass                     = ["AzureServices"]
    ip_rules                   = []
    virtual_network_subnet_ids = []
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

# Store storage connection string in Key Vault (best practice)
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name         = "storage-connection-string"
  value        = azurerm_storage_account.main.primary_connection_string
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
    # Use Key Vault reference for storage connection (Microsoft best practice)
    "AzureWebJobsStorage"             = "@Microsoft.KeyVault(VaultName=${azurerm_key_vault.main.name};SecretName=storage-connection-string)"
    "AZURE_OPENAI_DEPLOYMENT"         = var.azure_openai_deployment
    "WEBSITE_ENABLE_SYNC_UPDATE_SITE" = "true"
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

# Grant Functions access to Storage Blob (for configs/state)
resource "azurerm_role_assignment" "func_blob" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# Grant Functions access to Storage Table (if needed)
resource "azurerm_role_assignment" "func_table" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

# =============================================================================
# Container Apps - Agent (core) and OpenClaw Gateway (optional)
# =============================================================================

# Shared Container Apps Environment
resource "azurerm_container_app_environment" "main" {
  name                       = "${local.resource_prefix}-cae"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  tags = local.tags
}

# Azure Container Registry (optional — GHCR is free for public repos)
resource "random_string" "acr_suffix" {
  count   = var.enable_acr ? 1 : 0
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_container_registry" "main" {
  count               = var.enable_acr ? 1 : 0
  name                = "${replace(local.resource_prefix, "-", "")}acr${random_string.acr_suffix[0].result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true

  tags = local.tags
}

# MoltBot Agent Container App
resource "azurerm_container_app" "agent" {
  name                         = "${local.resource_prefix}-agent"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  # ACR registry credentials (only when ACR is enabled)
  dynamic "registry" {
    for_each = var.enable_acr ? [1] : []
    content {
      server               = azurerm_container_registry.main[0].login_server
      username             = azurerm_container_registry.main[0].admin_username
      password_secret_name = "acr-password"
    }
  }

  # ACR password secret (only when ACR is enabled)
  dynamic "secret" {
    for_each = var.enable_acr ? [1] : []
    content {
      name  = "acr-password"
      value = azurerm_container_registry.main[0].admin_password
    }
  }

  template {
    min_replicas = 0 # Scale to zero when idle for cost savings
    max_replicas = 2

    container {
      name   = "agent"
      image  = var.agent_container_image
      cpu    = 0.25
      memory = "0.5Gi"

      env {
        name  = "STORAGE_ACCOUNT_NAME"
        value = azurerm_storage_account.main.name
      }
      env {
        name  = "QUEUE_NAME"
        value = azurerm_storage_queue.work.name
      }
      env {
        name  = "KEY_VAULT_URI"
        value = azurerm_key_vault.main.vault_uri
      }
      env {
        name  = "AZURE_OPENAI_DEPLOYMENT"
        value = var.azure_openai_deployment
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.main.connection_string
      }
      env {
        name  = "PORT"
        value = "8080"
      }
    }
  }

  ingress {
    external_enabled = false # Internal only — Functions handle external webhooks
    target_port      = 8080
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = local.tags
}

# Agent role assignments (Managed Identity)
resource "azurerm_role_assignment" "agent_kv" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.agent.identity[0].principal_id
}

resource "azurerm_role_assignment" "agent_blob" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_container_app.agent.identity[0].principal_id
}

resource "azurerm_role_assignment" "agent_queue" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_container_app.agent.identity[0].principal_id
}

resource "azurerm_role_assignment" "agent_table" {
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_container_app.agent.identity[0].principal_id
}

# =============================================================================
# OpenClaw Gateway - Azure Container App (Optional)
# Provides enhanced AI capabilities: skills, multi-channel, session management
# =============================================================================

# OpenClaw Gateway Container App
resource "azurerm_container_app" "openclaw_gateway" {
  count                        = var.enable_openclaw ? 1 : 0
  name                         = "${local.resource_prefix}-openclaw"
  container_app_environment_id = azurerm_container_app_environment.main.id
  resource_group_name          = azurerm_resource_group.main.name
  revision_mode                = "Single"

  identity {
    type = "SystemAssigned"
  }

  template {
    min_replicas = 1 # Gateway needs to stay running for WebSocket connections
    max_replicas = 1 # Single instance for session state

    container {
      name   = "openclaw-gateway"
      image  = "ghcr.io/openclaw/openclaw:latest"
      cpu    = 0.5
      memory = "1Gi"

      # OpenClaw Gateway configuration
      env {
        name  = "OPENCLAW_BIND"
        value = "0.0.0.0"
      }
      env {
        name  = "OPENCLAW_PORT"
        value = "18789"
      }
      env {
        name  = "OPENCLAW_MODEL"
        value = var.openclaw_model
      }
      env {
        name  = "OPENCLAW_THINKING"
        value = var.openclaw_thinking
      }
      env {
        name        = "OPENCLAW_GATEWAY_TOKEN"
        secret_name = "gateway-token"
      }
      # Telegram channel (reuse existing bot token)
      env {
        name        = "TELEGRAM_BOT_TOKEN"
        secret_name = "telegram-token"
      }
      # Azure OpenAI as fallback model provider
      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = var.azure_openai_endpoint
      }
      env {
        name  = "AZURE_OPENAI_DEPLOYMENT"
        value = var.azure_openai_deployment
      }
      env {
        name        = "AZURE_OPENAI_API_KEY"
        secret_name = "aoai-key"
      }
    }
  }

  secret {
    name  = "gateway-token"
    value = var.openclaw_gateway_token != "" ? var.openclaw_gateway_token : "moltbot-gateway-${random_string.openclaw_token[0].result}"
  }

  secret {
    name  = "aoai-key"
    value = var.azure_openai_api_key
  }

  secret {
    name  = "telegram-token"
    value = var.telegram_bot_token
  }

  ingress {
    external_enabled = true
    target_port      = 18789
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  tags = local.tags
}

# Random token for OpenClaw Gateway auth (if user doesn't provide one)
resource "random_string" "openclaw_token" {
  count   = var.enable_openclaw ? 1 : 0
  length  = 32
  special = false
}

# Grant OpenClaw Gateway access to Key Vault
resource "azurerm_role_assignment" "openclaw_kv" {
  count                = var.enable_openclaw ? 1 : 0
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_container_app.openclaw_gateway[0].identity[0].principal_id
}

# Grant OpenClaw Gateway access to Storage (for state persistence)
resource "azurerm_role_assignment" "openclaw_storage" {
  count                = var.enable_openclaw ? 1 : 0
  scope                = azurerm_storage_account.main.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_container_app.openclaw_gateway[0].identity[0].principal_id
}

# Store OpenClaw Gateway token in Key Vault
resource "azurerm_key_vault_secret" "openclaw_gateway_token" {
  count        = var.enable_openclaw ? 1 : 0
  name         = "openclaw-gateway-token"
  value        = var.openclaw_gateway_token != "" ? var.openclaw_gateway_token : "moltbot-gateway-${random_string.openclaw_token[0].result}"
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_role_assignment.deployer_kv]
}
