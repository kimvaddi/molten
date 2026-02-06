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
  default     = "Allow"  # Changed from Deny to allow deployment, secured via RBAC

  validation {
    condition     = contains(["Allow", "Deny"], var.keyvault_network_default_action)
    error_message = "Must be 'Allow' or 'Deny'."
  }
}

# OpenClaw integration variables
variable "enable_acr" {
  description = "Enable Azure Container Registry (set false to use GHCR or pre-built images)"
  type        = bool
  default     = false
}

variable "agent_container_image" {
  description = "Container image for the agent (e.g., ghcr.io/kimvaddi/molten:latest)"
  type        = string
  default     = "ghcr.io/kimvaddi/molten:latest"
}

variable "enable_openclaw" {
  description = "Enable OpenClaw Gateway as an Azure Container App"
  type        = bool
  default     = false
}

variable "openclaw_model" {
  description = "OpenClaw model preference (e.g. anthropic/claude-sonnet-4-20250514)"
  type        = string
  default     = "anthropic/claude-sonnet-4-20250514"
}

variable "openclaw_thinking" {
  description = "OpenClaw thinking level: off, minimal, low, medium, high, xhigh"
  type        = string
  default     = "low"
}

variable "openclaw_gateway_token" {
  description = "OpenClaw Gateway authentication token"
  type        = string
  sensitive   = true
  default     = ""
}

locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
