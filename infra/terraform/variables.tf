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
  description = "Function App plan SKU (Y1=Consumption/Free, B1=Basic, EP1=Premium)"
  type        = string
  default     = "B1"  # B1 works in most enterprise subscriptions
}

locals {
  resource_prefix = "${var.project_name}-${var.environment}"
  tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
