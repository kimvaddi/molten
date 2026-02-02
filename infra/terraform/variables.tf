variable "location" {
  description = "Azure region"
  type        = string
  default     = "westus3"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "molten"
}

variable "azure_openai_endpoint" {
  description = "Azure OpenAI endpoint URL"
  type        = string
  sensitive   = true
}

variable "azure_openai_deployment" {
  description = "Azure OpenAI deployment name"
  type        = string
  default     = "gpt-4o-mini"
}

variable "azure_openai_api_key" {
  description = "Azure OpenAI API key"
  type        = string
  sensitive   = true
}

variable "telegram_bot_token" {
  description = "Telegram bot token"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_slack" {
  description = "Enable Slack integration"
  type        = bool
  default     = false
}

variable "enable_discord" {
  description = "Enable Discord integration"
  type        = bool
  default     = false
}

variable "function_plan_sku" {
  description = "Function App plan SKU (Y1=Consumption/Free, B1=Basic)"
  type        = string
  default     = "Y1"  # Consumption tier - FREE
}

variable "keyvault_network_default_action" {
  description = "Key Vault network ACL default action. Use 'Deny' for production with private endpoints."
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.keyvault_network_default_action)
    error_message = "Must be 'Allow' or 'Deny'."
  }
}

locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
