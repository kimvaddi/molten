# =============================================================================
# Molten - Terraform Outputs
# =============================================================================

# Resource Group
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.main.id
}

# Storage Account
output "storage_account_name" {
  description = "Name of the storage account"
  value       = azurerm_storage_account.main.name
}

output "storage_account_id" {
  description = "ID of the storage account"
  value       = azurerm_storage_account.main.id
}

output "storage_primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.main.primary_connection_string
  sensitive   = true
}

# Key Vault
output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.main.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.main.vault_uri
}

# Function App
output "function_app_name" {
  description = "Name of the Function App"
  value       = azurerm_linux_function_app.main.name
}

output "function_app_default_hostname" {
  description = "Default hostname of the Function App"
  value       = azurerm_linux_function_app.main.default_hostname
}

output "function_app_url" {
  description = "URL of the Function App"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}"
}

output "function_app_principal_id" {
  description = "Principal ID of the Function App Managed Identity"
  value       = azurerm_linux_function_app.main.identity[0].principal_id
}

# Webhook URLs
output "telegram_webhook_url" {
  description = "Telegram webhook URL"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/telegram"
}

output "slack_webhook_url" {
  description = "Slack webhook URL"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/slack"
}

output "discord_webhook_url" {
  description = "Discord webhook URL"
  value       = "https://${azurerm_linux_function_app.main.default_hostname}/api/discord"
}

# Application Insights
output "application_insights_name" {
  description = "Name of Application Insights"
  value       = azurerm_application_insights.main.name
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

# Log Analytics
output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

# Deployment Info
output "deployment_info" {
  description = "Deployment information summary"
  value = {
    project      = var.project_name
    environment  = var.environment
    region       = var.location
    function_url = "https://${azurerm_linux_function_app.main.default_hostname}"
    key_vault    = azurerm_key_vault.main.name
  }
}
