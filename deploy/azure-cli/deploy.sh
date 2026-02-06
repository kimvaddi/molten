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
    
    local missing=0
    
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Install from https://docs.microsoft.com/cli/azure/install-azure-cli"
        missing=1
    fi
    
    if ! command -v node &> /dev/null; then
        log_error "Node.js not found. Install from https://nodejs.org/ (v20+ required)"
        missing=1
    else
        NODE_VER=$(node --version | sed 's/v//' | cut -d. -f1)
        if [ "$NODE_VER" -lt 20 ]; then
            log_error "Node.js v20+ required (found v$NODE_VER). Update from https://nodejs.org/"
            missing=1
        fi
    fi
    
    if ! command -v func &> /dev/null; then
        log_warn "Azure Functions Core Tools not found. Install from https://docs.microsoft.com/azure/azure-functions/functions-run-local"
        log_warn "You won't be able to auto-deploy Function App code."
    fi
    
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found. Install from https://www.docker.com/"
        log_warn "You won't be able to build the agent container locally. ACR Build will be used if available."
    fi
    
    if [ $missing -eq 1 ]; then
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Run 'az login' first."
        exit 1
    fi
    
    log_info "Prerequisites OK (Azure CLI, Node.js v$NODE_VER)"
}

# =============================================================================
# Create Azure OpenAI Resource (Optional)
# =============================================================================
create_openai_resource() {
    local OPENAI_NAME="${PROJECT_NAME}-${ENVIRONMENT}-openai"
    log_info "Creating Azure OpenAI resource: $OPENAI_NAME"
    
    az cognitiveservices account create \
        --name "$OPENAI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --kind OpenAI \
        --sku S0 \
        --location "$LOCATION" \
        --yes
    
    log_info "Deploying gpt-4o-mini model..."
    az cognitiveservices account deployment create \
        --name "$OPENAI_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --deployment-name gpt-4o-mini \
        --model-name gpt-4o-mini \
        --model-version "2024-07-18" \
        --model-format OpenAI \
        --sku-capacity 10 \
        --sku-name Standard
    
    AZURE_OPENAI_ENDPOINT=$(az cognitiveservices account show \
        --name "$OPENAI_NAME" --resource-group "$RESOURCE_GROUP" \
        --query properties.endpoint -o tsv)
    AZURE_OPENAI_API_KEY=$(az cognitiveservices account keys list \
        --name "$OPENAI_NAME" --resource-group "$RESOURCE_GROUP" \
        --query key1 -o tsv)
    AZURE_OPENAI_DEPLOYMENT="gpt-4o-mini"
    
    log_info "Azure OpenAI created: $AZURE_OPENAI_ENDPOINT"
}

# =============================================================================
# Validate Azure OpenAI Endpoint
# =============================================================================
validate_openai() {
    log_info "Validating Azure OpenAI endpoint..."
    
    local STATUS
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "api-key: $AZURE_OPENAI_API_KEY" \
        "${AZURE_OPENAI_ENDPOINT}openai/deployments/${AZURE_OPENAI_DEPLOYMENT}/chat/completions?api-version=2024-02-01" \
        -H "Content-Type: application/json" \
        -d '{"messages":[{"role":"user","content":"test"}],"max_tokens":1}')
    
    if [ "$STATUS" = "200" ]; then
        log_info "OpenAI endpoint validated successfully"
    elif [ "$STATUS" = "429" ]; then
        log_info "OpenAI endpoint reachable (rate limited — normal for S0 tier)"
    else
        log_warn "OpenAI endpoint returned HTTP $STATUS. Deployment will continue but check your endpoint/key."
    fi
}

# =============================================================================
# Get User Inputs
# =============================================================================
get_inputs() {
    echo ""
    log_info "Molten Deployment Configuration"
    echo "================================"
    echo ""
    echo "Do you already have an Azure OpenAI resource, or should this script create one?"
    echo "  1) I already have an endpoint and API key"
    echo "  2) Create a new Azure OpenAI resource for me (auto)"
    read -p "Choice [1]: " OPENAI_CHOICE
    OPENAI_CHOICE=${OPENAI_CHOICE:-1}
    
    if [ "$OPENAI_CHOICE" = "2" ]; then
        AUTO_CREATE_OPENAI=true
        log_info "Will auto-create Azure OpenAI resource after resource group is created."
    else
        AUTO_CREATE_OPENAI=false
        read -p "Azure OpenAI Endpoint URL: " AZURE_OPENAI_ENDPOINT
        read -sp "Azure OpenAI API Key: " AZURE_OPENAI_API_KEY
        echo ""
        read -p "Azure OpenAI Deployment Name [gpt-4o-mini]: " AZURE_OPENAI_DEPLOYMENT
        AZURE_OPENAI_DEPLOYMENT=${AZURE_OPENAI_DEPLOYMENT:-gpt-4o-mini}
    fi
    
    read -p "Telegram Bot Token (optional — get one from @BotFather on Telegram): " TELEGRAM_BOT_TOKEN
    
    echo ""
    log_info "Configuration:"
    echo "  Resource Group: $RESOURCE_GROUP"
    echo "  Location: $LOCATION"
    if [ "$AUTO_CREATE_OPENAI" = true ]; then
        echo "  OpenAI: Will be auto-created"
    else
        echo "  OpenAI Endpoint: $AZURE_OPENAI_ENDPOINT"
        echo "  OpenAI Deployment: $AZURE_OPENAI_DEPLOYMENT"
    fi
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
# Create Agent Container App
# =============================================================================
create_container_app() {
    CAE_NAME="${PROJECT_NAME}-${ENVIRONMENT}-cae"
    AGENT_NAME="${PROJECT_NAME}-${ENVIRONMENT}-agent"
    KEY_VAULT_NAME="${PROJECT_NAME}-${ENVIRONMENT}-kv"
    STORAGE_NAME="${PROJECT_NAME}${ENVIRONMENT}stor"
    APP_INSIGHTS_NAME="${PROJECT_NAME}-${ENVIRONMENT}-insights"
    LOG_ANALYTICS_NAME="${PROJECT_NAME}-${ENVIRONMENT}-logs"

    log_info "Creating Container Apps Environment: $CAE_NAME"

    LOG_ANALYTICS_CUSTOMER_ID=$(az monitor log-analytics workspace show \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query customerId -o tsv)

    LOG_ANALYTICS_KEY=$(az monitor log-analytics workspace get-shared-keys \
        --workspace-name "$LOG_ANALYTICS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query primarySharedKey -o tsv)

    az containerapp env create \
        --name "$CAE_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --logs-workspace-id "$LOG_ANALYTICS_CUSTOMER_ID" \
        --logs-workspace-key "$LOG_ANALYTICS_KEY"

    APP_INSIGHTS_CONN=$(az monitor app-insights component show \
        --app "$APP_INSIGHTS_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query connectionString -o tsv)

    log_info "Creating Agent Container App: $AGENT_NAME"

    az containerapp create \
        --name "$AGENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --environment "$CAE_NAME" \
        --image "${AGENT_IMAGE:-ghcr.io/kimvaddi/molten:latest}" \
        --cpu 0.25 \
        --memory 0.5Gi \
        --min-replicas 0 \
        --max-replicas 2 \
        --ingress internal \
        --target-port 8080 \
        --transport http \
        --system-assigned \
        --env-vars \
            "STORAGE_ACCOUNT_NAME=$STORAGE_NAME" \
            "QUEUE_NAME=molten-work" \
            "KEY_VAULT_URI=https://${KEY_VAULT_NAME}.vault.azure.net/" \
            "AZURE_OPENAI_DEPLOYMENT=$AZURE_OPENAI_DEPLOYMENT" \
            "APPLICATIONINSIGHTS_CONNECTION_STRING=$APP_INSIGHTS_CONN" \
            "PORT=8080"

    # Get Agent identity and grant RBAC roles
    AGENT_PRINCIPAL_ID=$(az containerapp identity show \
        --name "$AGENT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query principalId -o tsv)

    KEY_VAULT_ID=$(az keyvault show --name "$KEY_VAULT_NAME" --query id -o tsv)
    STORAGE_ID=$(az storage account show --name "$STORAGE_NAME" --query id -o tsv)

    log_info "Granting Agent Managed Identity roles..."

    az role assignment create --role "Key Vault Secrets User" \
        --assignee "$AGENT_PRINCIPAL_ID" --scope "$KEY_VAULT_ID"
    az role assignment create --role "Storage Queue Data Contributor" \
        --assignee "$AGENT_PRINCIPAL_ID" --scope "$STORAGE_ID"
    az role assignment create --role "Storage Blob Data Contributor" \
        --assignee "$AGENT_PRINCIPAL_ID" --scope "$STORAGE_ID"
    az role assignment create --role "Storage Table Data Contributor" \
        --assignee "$AGENT_PRINCIPAL_ID" --scope "$STORAGE_ID"

    log_info "Agent Container App created with Managed Identity"
}

# =============================================================================
# Deploy Function App Code
# =============================================================================
deploy_function_code() {
    FUNC_APP_NAME="${PROJECT_NAME}-${ENVIRONMENT}-func"
    
    if ! command -v func &> /dev/null; then
        log_warn "Azure Functions Core Tools not installed — skipping Function App code deployment."
        log_warn "Deploy manually: cd src/functions && npm install && npm run build && func azure functionapp publish $FUNC_APP_NAME"
        return
    fi
    
    log_info "Deploying Function App code to $FUNC_APP_NAME..."
    ORIG_DIR=$(pwd)
    cd src/functions
    npm install --production
    npm run build
    func azure functionapp publish "$FUNC_APP_NAME" --nozip
    cd "$ORIG_DIR"
    log_info "Function App code deployed"
}

# =============================================================================
# Deploy Agent Container
# =============================================================================
deploy_agent_container() {
    AGENT_NAME="${PROJECT_NAME}-${ENVIRONMENT}-agent"
    AGENT_IMAGE="${AGENT_IMAGE:-ghcr.io/kimvaddi/molten:latest}"
    
    log_info "Agent container image: $AGENT_IMAGE"
    log_info "To update the agent image later:"
    echo "  az containerapp update -n $AGENT_NAME -g $RESOURCE_GROUP --image <your-image>"
}

# =============================================================================
# Register Telegram Webhook
# =============================================================================
register_telegram_webhook() {
    if [ -z "$TELEGRAM_BOT_TOKEN" ]; then
        log_warn "No Telegram bot token provided — skipping webhook registration."
        log_warn "Set it later: curl -X POST \"https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://${PROJECT_NAME}-${ENVIRONMENT}-func.azurewebsites.net/api/telegram\""
        return
    fi
    
    FUNC_APP_NAME="${PROJECT_NAME}-${ENVIRONMENT}-func"
    WEBHOOK_URL="https://${FUNC_APP_NAME}.azurewebsites.net/api/telegram"
    
    log_info "Registering Telegram webhook: $WEBHOOK_URL"
    RESPONSE=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook?url=${WEBHOOK_URL}")
    
    if echo "$RESPONSE" | grep -q '"ok":true'; then
        log_info "Telegram webhook registered successfully"
    else
        log_warn "Telegram webhook registration response: $RESPONSE"
        log_warn "You can retry manually: curl -X POST \"https://api.telegram.org/bot<TOKEN>/setWebhook?url=$WEBHOOK_URL\""
    fi
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
    echo "  Agent Container App: ${PROJECT_NAME}-${ENVIRONMENT}-agent"
    echo "  Key Vault: ${PROJECT_NAME}-${ENVIRONMENT}-kv"
    echo "  Storage: ${PROJECT_NAME}${ENVIRONMENT}stor"
    echo ""
    echo "Webhook URLs:"
    echo "  Telegram: https://${FUNC_APP_NAME}.azurewebsites.net/api/telegram"
    echo "  Slack: https://${FUNC_APP_NAME}.azurewebsites.net/api/slack"
    echo "  Discord: https://${FUNC_APP_NAME}.azurewebsites.net/api/discord"
    echo ""
    echo "Verify your bot:"
    echo "  1. Open Telegram and find your bot by username"
    echo "  2. Send: Hello!"
    echo "  3. Check logs if no response: az containerapp logs show -n ${PROJECT_NAME}-${ENVIRONMENT}-agent -g $RESOURCE_GROUP --tail 20"
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
    
    # Auto-create Azure OpenAI if requested
    if [ "$AUTO_CREATE_OPENAI" = true ]; then
        create_openai_resource
    fi
    
    # Validate OpenAI before proceeding
    validate_openai
    
    create_storage_account
    create_key_vault
    create_monitoring
    create_function_app
    create_container_app
    deploy_function_code
    deploy_agent_container
    register_telegram_webhook
    print_summary
}

main
