#!/bin/bash
# =============================================================================
# Molten - Azure CLI Deployment Script
# =============================================================================
# This script deploys Molten infrastructure using Azure CLI
# Run from the repository root directory
#
# SECURITY WARNING:
# This script prompts for secrets interactively. To protect your secrets:
# - Do NOT commit terminal output or logs containing secrets
# - Clear shell history after running: history -c
# - Never copy-paste secrets into files that might be committed
# - Secrets are stored securely in Azure Key Vault after entry
# =============================================================================

set -e

# Configuration
PROJECT_NAME="molten"
ENVIRONMENT="dev"
LOCATION="westus3"
RESOURCE_GROUP="${PROJECT_NAME}-${ENVIRONMENT}-rg"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# =============================================================================
# Prerequisites Check
# =============================================================================
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Install from https://docs.microsoft.com/cli/azure/install-azure-cli"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi
    
    log_info "Prerequisites OK"
}

# =============================================================================
# Get User Inputs
# =============================================================================
get_inputs() {
    echo ""
    log_info "Molten Deployment Configuration"
    echo "================================"
    
    read -p "Azure OpenAI Endpoint URL: " AZURE_OPENAI_ENDPOINT
    read -sp "Azure OpenAI API Key: " AZURE_OPENAI_API_KEY
    echo ""
    read -p "Azure OpenAI Deployment Name [gpt-4o-mini]: " AZURE_OPENAI_DEPLOYMENT
    AZURE_OPENAI_DEPLOYMENT=${AZURE_OPENAI_DEPLOYMENT:-gpt-4o-mini}
    read -p "Telegram Bot Token (optional): " TELEGRAM_BOT_TOKEN
    
    echo ""
    log_info "Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    echo "  OpenAI Deployment: $AZURE_OPENAI_DEPLOYMENT"
}

# =============================================================================
# Create Resource Group
# =============================================================================
create_resource_group() {
    log_info "Creating resource group: $RESOURCE_GROUP"
    az group create \
        --name "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --tags Project="$PROJECT_NAME" Environment="$ENVIRONMENT" ManagedBy="AzureCLI"
}

# =============================================================================
# Create Storage Account
# =============================================================================
create_storage_account() {
    STORAGE_NAME="${PROJECT_NAME}${ENVIRONMENT}stor"
    log_info "Creating storage account: $STORAGE_NAME"
    
    az storage account create \
        --name "$STORAGE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Standard_LRS \
        --min-tls-version TLS1_2 \
        --allow-blob-public-access false
    
    # Create queue and blob container
    STORAGE_KEY=$(az storage account keys list --account-name "$STORAGE_NAME" --query '[0].value' -o tsv)
    
    az storage queue create \
        --name "molten-work" \
        --account-name "$STORAGE_NAME" \
        --account-key "$STORAGE_KEY"
    
    az storage container create \
        --name "molten-configs" \
        --account-name "$STORAGE_NAME" \
        --account-key "$STORAGE_KEY"
    
    log_info "Storage account created"
}

# =============================================================================
# Create Key Vault
# =============================================================================
create_key_vault() {
    KEY_VAULT_NAME="${PROJECT_NAME}-${ENVIRONMENT}-kv"
    log_info "Creating Key Vault: $KEY_VAULT_NAME"
    
    az keyvault create \
        --name "$KEY_VAULT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku standard \
        --enable-rbac-authorization true
    
    # Get current user for RBAC
    CURRENT_USER_ID=$(az ad signed-in-user show --query id -o tsv)
    KEY_VAULT_ID=$(az keyvault show --name "$KEY_VAULT_NAME" --query id -o tsv)
    
    # Grant secrets access
    az role assignment create \
        --role "Key Vault Secrets Officer" \
        --assignee "$CURRENT_USER_ID" \
        --scope "$KEY_VAULT_ID"
    
    # Wait for RBAC propagation
    sleep 30
    
    # Add secrets
    az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "azure-openai-endpoint" --value "$AZURE_OPENAI_ENDPOINT"
    az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "azure-openai-api-key" --value "$AZURE_OPENAI_API_KEY"
    
    if [ -n "$TELEGRAM_BOT_TOKEN" ]; then
        az keyvault secret set --vault-name "$KEY_VAULT_NAME" --name "telegram-bot-token" --value "$TELEGRAM_BOT_TOKEN"
    fi
    
    log_info "Key Vault created and secrets added"
}

# =============================================================================
# Create Log Analytics & Application Insights
# =============================================================================
create_monitoring() {
    LOG_ANALYTICS_NAME="${PROJECT_NAME}-${ENVIRONMENT}-logs"
    APP_INSIGHTS_NAME="${PROJECT_NAME}-${ENVIRONMENT}-insights"
    
    log_info "Creating Log Analytics workspace: $LOG_ANALYTICS_NAME"
    az monitor log-analytics workspace create \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --retention-time 30
    
    LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query id -o tsv)
    
    log_info "Creating Application Insights: $APP_INSIGHTS_NAME"
    az monitor app-insights component create \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --workspace "$LOG_ANALYTICS_ID" \
        --application-type Node.JS
    
    log_info "Monitoring resources created"
}

# =============================================================================
# Create Function App
# =============================================================================
create_function_app() {
    FUNC_PLAN_NAME="${PROJECT_NAME}-${ENVIRONMENT}-func-plan"
    FUNC_APP_NAME="${PROJECT_NAME}-${ENVIRONMENT}-func"
    STORAGE_NAME="${PROJECT_NAME}${ENVIRONMENT}stor"
    KEY_VAULT_NAME="${PROJECT_NAME}-${ENVIRONMENT}-kv"
    APP_INSIGHTS_NAME="${PROJECT_NAME}-${ENVIRONMENT}-insights"
    
    log_info "Creating Function App: $FUNC_APP_NAME"
    
    # Get App Insights connection string
    APP_INSIGHTS_CONN=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString -o tsv)
    
    # Create consumption plan
    az functionapp plan create \
        --name "$FUNC_PLAN_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku Y1 \
        --is-linux
    
    # Create function app
    az functionapp create \
        --name "$FUNC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --plan "$FUNC_PLAN_NAME" \
        --storage-account "$STORAGE_NAME" \
        --runtime node \
        --runtime-version 20 \
        --functions-version 4 \
        --assign-identity '[system]'
    
    # Get Function App identity
    FUNC_PRINCIPAL_ID=$(az functionapp identity show \
        --name "$FUNC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId -o tsv)
    
    # Grant Key Vault access
    KEY_VAULT_ID=$(az keyvault show --name "$KEY_VAULT_NAME" --query id -o tsv)
    az role assignment create \
        --role "Key Vault Secrets User" \
        --assignee "$FUNC_PRINCIPAL_ID" \
        --scope "$KEY_VAULT_ID"
    
    # Grant Storage access
    STORAGE_ID=$(az storage account show --name "$STORAGE_NAME" --query id -o tsv)
    az role assignment create \
        --role "Storage Queue Data Contributor" \
        --assignee "$FUNC_PRINCIPAL_ID" \
        --scope "$STORAGE_ID"
    
    # Configure app settings
    az functionapp config appsettings set \
        --name "$FUNC_APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings \
            "FUNCTIONS_WORKER_RUNTIME=node" \
            "QUEUE_NAME=molten-work" \
            "KEY_VAULT_URI=https://${KEY_VAULT_NAME}.vault.azure.net/" \
            "STORAGE_ACCOUNT_NAME=$STORAGE_NAME" \
            "AZURE_OPENAI_DEPLOYMENT=$AZURE_OPENAI_DEPLOYMENT" \
            "APPLICATIONINSIGHTS_CONNECTION_STRING=$APP_INSIGHTS_CONN"
    
    log_info "Function App created"
}

# =============================================================================
# Print Summary
# =============================================================================
print_summary() {
    FUNC_APP_NAME="${PROJECT_NAME}-${ENVIRONMENT}-func"
    
    echo ""
    echo "============================================="
    log_info "Deployment Complete!"
    echo "============================================="
    echo ""
    echo "Resources Created:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Function App: $FUNC_APP_NAME"
    echo "  Key Vault: ${PROJECT_NAME}-${ENVIRONMENT}-kv"
    echo "  Storage: ${PROJECT_NAME}${ENVIRONMENT}stor"
    echo ""
    echo "Webhook URLs:"
    echo "  Telegram: https://${FUNC_APP_NAME}.azurewebsites.net/api/telegram"
    echo "  Slack: https://${FUNC_APP_NAME}.azurewebsites.net/api/slack"
    echo "  Discord: https://${FUNC_APP_NAME}.azurewebsites.net/api/discord"
    echo ""
    echo "Next Steps:"
    echo "  1. cd src/functions && npm install && npm run build"
    echo "  2. func azure functionapp publish $FUNC_APP_NAME"
    echo "  3. Configure Telegram webhook:"
    echo "     curl -X POST \"https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://${FUNC_APP_NAME}.azurewebsites.net/api/telegram\""
    echo ""
}

# =============================================================================
# Main
# =============================================================================
main() {
    echo "============================================="
    echo "  Molten - Azure Deployment Script"
    echo "============================================="
    
    check_prerequisites
    get_inputs
    
    echo ""
    read -p "Proceed with deployment? (y/N): " CONFIRM
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        log_warn "Deployment cancelled"
        exit 0
    fi
    
    create_resource_group
    create_storage_account
    create_key_vault
    create_monitoring
    create_function_app
    print_summary
}

main
