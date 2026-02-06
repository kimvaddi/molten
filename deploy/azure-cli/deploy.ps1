# =============================================================================
# Molten - Azure CLI Deployment Script (PowerShell Wrapper)
# =============================================================================
# This script deploys Molten infrastructure using Azure CLI from PowerShell
# Run from the repository root directory
#
# SECURITY WARNING:
# This script prompts for secrets interactively. To protect your secrets:
# - Do NOT commit terminal output or logs containing secrets
# - Clear PowerShell history: Clear-History; Remove-Item (Get-PSReadlineOption).HistorySavePath
# - Never copy-paste secrets into files that might be committed
# - Secrets are stored securely in Azure Key Vault after entry
# =============================================================================

$ErrorActionPreference = "Stop"

# Configuration
$ProjectName = "molten"
$Environment = "dev"
$Location = "westus3"
$ResourceGroup = "$ProjectName-$Environment-rg"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $color = switch ($Level) {
        "INFO" { "Green" }
        "WARN" { "Yellow" }
        "ERROR" { "Red" }
        default { "White" }
    }
    Write-Host "[$Level] $Message" -ForegroundColor $color
}

# =============================================================================
# Prerequisites Check
# =============================================================================
function Test-Prerequisites {
    Write-Log "Checking prerequisites..."
    
    if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
        Write-Log "Azure CLI not found. Install from https://docs.microsoft.com/cli/azure/install-azure-cli" "ERROR"
        exit 1
    }
    
    $account = az account show 2>$null | ConvertFrom-Json
    if (-not $account) {
        Write-Log "Not logged in to Azure. Run 'az login' first." "ERROR"
        exit 1
    }
    
    Write-Log "Prerequisites OK - Logged in as: $($account.user.name)"
}

# =============================================================================
# Get User Inputs
# =============================================================================
function Get-DeploymentInputs {
    Write-Host ""
    Write-Log "Molten Deployment Configuration"
    Write-Host "================================"
    
    $script:AzureOpenAIEndpoint = Read-Host "Azure OpenAI Endpoint URL"
    $script:AzureOpenAIApiKey = Read-Host "Azure OpenAI API Key" -AsSecureString
    $script:AzureOpenAIApiKeyPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:AzureOpenAIApiKey))
    
    $deploymentInput = Read-Host "Azure OpenAI Deployment Name [gpt-4o-mini]"
    $script:AzureOpenAIDeployment = if ($deploymentInput) { $deploymentInput } else { "gpt-4o-mini" }
    
    $script:TelegramBotToken = Read-Host "Telegram Bot Token (optional)"
    
    Write-Host ""
    Write-Log "Configuration:"
    Write-Host "  Resource Group: $ResourceGroup"
    Write-Host "  Location: $Location"
    Write-Host "  OpenAI Deployment: $($script:AzureOpenAIDeployment)"
}

# =============================================================================
# Create Resource Group
# =============================================================================
function New-ResourceGroup {
    Write-Log "Creating resource group: $ResourceGroup"
    az group create `
        --name $ResourceGroup `
        --location $Location `
        --tags Project=$ProjectName Environment=$Environment ManagedBy=AzureCLI
}

# =============================================================================
# Create Storage Account
# =============================================================================
function New-StorageAccount {
    $storageName = "$ProjectName$($Environment)stor"
    Write-Log "Creating storage account: $storageName"
    
    az storage account create `
        --name $storageName `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku Standard_LRS `
        --min-tls-version TLS1_2 `
        --allow-blob-public-access false
    
    $storageKey = az storage account keys list --account-name $storageName --query '[0].value' -o tsv
    
    az storage queue create --name "molten-work" --account-name $storageName --account-key $storageKey
    az storage container create --name "molten-configs" --account-name $storageName --account-key $storageKey
    
    Write-Log "Storage account created"
}

# =============================================================================
# Create Key Vault
# =============================================================================
function New-KeyVault {
    $keyVaultName = "$ProjectName-$Environment-kv"
    Write-Log "Creating Key Vault: $keyVaultName"
    
    az keyvault create `
        --name $keyVaultName `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku standard `
        --enable-rbac-authorization true
    
    $currentUserId = az ad signed-in-user show --query id -o tsv
    $keyVaultId = az keyvault show --name $keyVaultName --query id -o tsv
    
    az role assignment create `
        --role "Key Vault Secrets Officer" `
        --assignee $currentUserId `
        --scope $keyVaultId
    
    Write-Log "Waiting for RBAC propagation..."
    Start-Sleep -Seconds 30
    
    az keyvault secret set --vault-name $keyVaultName --name "azure-openai-endpoint" --value $script:AzureOpenAIEndpoint
    az keyvault secret set --vault-name $keyVaultName --name "azure-openai-api-key" --value $script:AzureOpenAIApiKeyPlain
    
    if ($script:TelegramBotToken) {
        az keyvault secret set --vault-name $keyVaultName --name "telegram-bot-token" --value $script:TelegramBotToken
    }
    
    Write-Log "Key Vault created and secrets added"
}

# =============================================================================
# Create Monitoring Resources
# =============================================================================
function New-MonitoringResources {
    $logAnalyticsName = "$ProjectName-$Environment-logs"
    $appInsightsName = "$ProjectName-$Environment-insights"
    
    Write-Log "Creating Log Analytics workspace: $logAnalyticsName"
    az monitor log-analytics workspace create `
        --workspace-name $logAnalyticsName `
        --resource-group $ResourceGroup `
        --location $Location `
        --retention-time 30
    
    $logAnalyticsId = az monitor log-analytics workspace show `
        --workspace-name $logAnalyticsName `
        --resource-group $ResourceGroup `
        --query id -o tsv
    
    Write-Log "Creating Application Insights: $appInsightsName"
    az monitor app-insights component create `
        --app $appInsightsName `
        --resource-group $ResourceGroup `
        --location $Location `
        --workspace $logAnalyticsId `
        --application-type Node.JS
    
    Write-Log "Monitoring resources created"
}

# =============================================================================
# Create Function App
# =============================================================================
function New-FunctionApp {
    $funcPlanName = "$ProjectName-$Environment-func-plan"
    $funcAppName = "$ProjectName-$Environment-func"
    $storageName = "$ProjectName$($Environment)stor"
    $keyVaultName = "$ProjectName-$Environment-kv"
    $appInsightsName = "$ProjectName-$Environment-insights"
    
    Write-Log "Creating Function App: $funcAppName"
    
    $appInsightsConn = az monitor app-insights component show `
        --app $appInsightsName `
        --resource-group $ResourceGroup `
        --query connectionString -o tsv
    
    az functionapp plan create `
        --name $funcPlanName `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku Y1 `
        --is-linux
    
    az functionapp create `
        --name $funcAppName `
        --resource-group $ResourceGroup `
        --plan $funcPlanName `
        --storage-account $storageName `
        --runtime node `
        --runtime-version 20 `
        --functions-version 4 `
        --assign-identity '[system]'
    
    $funcPrincipalId = az functionapp identity show `
        --name $funcAppName `
        --resource-group $ResourceGroup `
        --query principalId -o tsv
    
    $keyVaultId = az keyvault show --name $keyVaultName --query id -o tsv
    az role assignment create --role "Key Vault Secrets User" --assignee $funcPrincipalId --scope $keyVaultId
    
    $storageId = az storage account show --name $storageName --query id -o tsv
    az role assignment create --role "Storage Queue Data Contributor" --assignee $funcPrincipalId --scope $storageId
    
    az functionapp config appsettings set `
        --name $funcAppName `
        --resource-group $ResourceGroup `
        --settings `
            "FUNCTIONS_WORKER_RUNTIME=node" `
            "QUEUE_NAME=molten-work" `
            "KEY_VAULT_URI=https://$keyVaultName.vault.azure.net/" `
            "STORAGE_ACCOUNT_NAME=$storageName" `
            "AZURE_OPENAI_DEPLOYMENT=$($script:AzureOpenAIDeployment)" `
            "APPLICATIONINSIGHTS_CONNECTION_STRING=$appInsightsConn"
    
    Write-Log "Function App created"
}

# =============================================================================
# Create Agent Container App
# =============================================================================
function New-ContainerApp {
    $caeName = "$ProjectName-$Environment-cae"
    $agentName = "$ProjectName-$Environment-agent"
    $keyVaultName = "$ProjectName-$Environment-kv"
    $storageName = "$ProjectName$($Environment)stor"
    $appInsightsName = "$ProjectName-$Environment-insights"
    $logAnalyticsName = "$ProjectName-$Environment-logs"

    Write-Log "Creating Container Apps Environment: $caeName"

    $logCustomerId = az monitor log-analytics workspace show `
        --workspace-name $logAnalyticsName `
        --resource-group $ResourceGroup `
        --query customerId -o tsv

    $logKey = az monitor log-analytics workspace get-shared-keys `
        --workspace-name $logAnalyticsName `
        --resource-group $ResourceGroup `
        --query primarySharedKey -o tsv

    az containerapp env create `
        --name $caeName `
        --resource-group $ResourceGroup `
        --location $Location `
        --logs-workspace-id $logCustomerId `
        --logs-workspace-key $logKey

    $appInsightsConn = az monitor app-insights component show `
        --app $appInsightsName `
        --resource-group $ResourceGroup `
        --query connectionString -o tsv

    $agentImage = if ($env:AGENT_IMAGE) { $env:AGENT_IMAGE } else { "ghcr.io/kimvaddi/molten:latest" }

    Write-Log "Creating Agent Container App: $agentName"

    az containerapp create `
        --name $agentName `
        --resource-group $ResourceGroup `
        --environment $caeName `
        --image $agentImage `
        --cpu 0.25 `
        --memory 0.5Gi `
        --min-replicas 0 `
        --max-replicas 2 `
        --ingress internal `
        --target-port 8080 `
        --transport http `
        --system-assigned `
        --env-vars `
            "STORAGE_ACCOUNT_NAME=$storageName" `
            "QUEUE_NAME=molten-work" `
            "KEY_VAULT_URI=https://$keyVaultName.vault.azure.net/" `
            "AZURE_OPENAI_DEPLOYMENT=$($script:AzureOpenAIDeployment)" `
            "APPLICATIONINSIGHTS_CONNECTION_STRING=$appInsightsConn" `
            "PORT=8080"

    $agentPrincipalId = az containerapp identity show `
        --name $agentName `
        --resource-group $ResourceGroup `
        --query principalId -o tsv

    $keyVaultId = az keyvault show --name $keyVaultName --query id -o tsv
    $storageId = az storage account show --name $storageName --query id -o tsv

    Write-Log "Granting Agent Managed Identity roles..."

    az role assignment create --role "Key Vault Secrets User" --assignee $agentPrincipalId --scope $keyVaultId
    az role assignment create --role "Storage Queue Data Contributor" --assignee $agentPrincipalId --scope $storageId
    az role assignment create --role "Storage Blob Data Contributor" --assignee $agentPrincipalId --scope $storageId
    az role assignment create --role "Storage Table Data Contributor" --assignee $agentPrincipalId --scope $storageId

    Write-Log "Agent Container App created with Managed Identity"
}

# =============================================================================
# Print Summary
# =============================================================================
function Write-Summary {
    $funcAppName = "$ProjectName-$Environment-func"
    
    Write-Host ""
    Write-Host "============================================="
    Write-Log "Deployment Complete!"
    Write-Host "============================================="
    Write-Host ""
    Write-Host "Resources Created:"
    Write-Host "  Resource Group: $ResourceGroup"
    Write-Host "  Function App: $funcAppName"
    Write-Host "  Agent Container App: $ProjectName-$Environment-agent"
    Write-Host "  Key Vault: $ProjectName-$Environment-kv"
    Write-Host "  Storage: $ProjectName$($Environment)stor"
    Write-Host ""
    Write-Host "Webhook URLs:"
    Write-Host "  Telegram: https://$funcAppName.azurewebsites.net/api/telegram"
    Write-Host "  Slack: https://$funcAppName.azurewebsites.net/api/slack"
    Write-Host "  Discord: https://$funcAppName.azurewebsites.net/api/discord"
    Write-Host ""
    Write-Host "Next Steps:"
    Write-Host "  1. cd src/functions; npm install; npm run build"
    Write-Host "  2. func azure functionapp publish $funcAppName"
    Write-Host "  3. cd src/agent; docker build -t ghcr.io/kimvaddi/molten:latest ."
    Write-Host "  4. docker push ghcr.io/kimvaddi/molten:latest"
    Write-Host "  5. az containerapp update -n $ProjectName-$Environment-agent -g $ResourceGroup --image ghcr.io/kimvaddi/molten:latest"
    Write-Host ""
}

# =============================================================================
# Main
# =============================================================================
Write-Host "============================================="
Write-Host "  Molten - Azure Deployment Script"
Write-Host "============================================="

Test-Prerequisites
Get-DeploymentInputs

Write-Host ""
$confirm = Read-Host "Proceed with deployment? (y/N)"
if ($confirm -notmatch "^[Yy]$") {
    Write-Log "Deployment cancelled" "WARN"
    exit 0
}

New-ResourceGroup
New-StorageAccount
New-KeyVault
New-MonitoringResources
New-FunctionApp
New-ContainerApp
Write-Summary
