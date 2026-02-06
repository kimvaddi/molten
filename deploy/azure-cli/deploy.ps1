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
    
    $missing = $false
    
    if (-not (Get-Command "az" -ErrorAction SilentlyContinue)) {
        Write-Log "Azure CLI not found. Install from https://docs.microsoft.com/cli/azure/install-azure-cli" "ERROR"
        $missing = $true
    }
    
    if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
        Write-Log "Node.js not found. Install from https://nodejs.org/ (v20+ required)" "ERROR"
        $missing = $true
    } else {
        $nodeVer = (node --version) -replace 'v','' -split '\.' | Select-Object -First 1
        if ([int]$nodeVer -lt 20) {
            Write-Log "Node.js v20+ required (found v$nodeVer). Update from https://nodejs.org/" "ERROR"
            $missing = $true
        }
    }
    
    if (-not (Get-Command "func" -ErrorAction SilentlyContinue)) {
        Write-Log "Azure Functions Core Tools not found. Install from https://docs.microsoft.com/azure/azure-functions/functions-run-local" "WARN"
        Write-Log "You won't be able to auto-deploy Function App code." "WARN"
    }
    
    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        Write-Log "Docker not found. Install from https://www.docker.com/" "WARN"
        Write-Log "You won't be able to build the agent container locally. ACR Build will be used if available." "WARN"
    }
    
    if ($missing) {
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
# Create Azure OpenAI Resource (Optional)
# =============================================================================
function New-OpenAIResource {
    $openaiName = "$ProjectName-$Environment-openai"
    Write-Log "Creating Azure OpenAI resource: $openaiName"
    
    az cognitiveservices account create `
        --name $openaiName `
        --resource-group $ResourceGroup `
        --kind OpenAI `
        --sku S0 `
        --location $Location `
        --yes
    
    Write-Log "Deploying gpt-4o-mini model..."
    az cognitiveservices account deployment create `
        --name $openaiName `
        --resource-group $ResourceGroup `
        --deployment-name gpt-4o-mini `
        --model-name gpt-4o-mini `
        --model-version "2024-07-18" `
        --model-format OpenAI `
        --sku-capacity 10 `
        --sku-name Standard
    
    $script:AzureOpenAIEndpoint = az cognitiveservices account show `
        --name $openaiName --resource-group $ResourceGroup `
        --query properties.endpoint -o tsv
    $script:AzureOpenAIApiKeyPlain = az cognitiveservices account keys list `
        --name $openaiName --resource-group $ResourceGroup `
        --query key1 -o tsv
    $script:AzureOpenAIDeployment = "gpt-4o-mini"
    
    Write-Log "Azure OpenAI created: $($script:AzureOpenAIEndpoint)"
}

# =============================================================================
# Validate Azure OpenAI Endpoint
# =============================================================================
function Test-OpenAIEndpoint {
    Write-Log "Validating Azure OpenAI endpoint..."
    
    try {
        $headers = @{ "api-key" = $script:AzureOpenAIApiKeyPlain; "Content-Type" = "application/json" }
        $body = '{"messages":[{"role":"user","content":"test"}],"max_tokens":1}'
        $uri = "$($script:AzureOpenAIEndpoint)openai/deployments/$($script:AzureOpenAIDeployment)/chat/completions?api-version=2024-02-01"
        $response = Invoke-WebRequest -Uri $uri -Method Post -Headers $headers -Body $body -ErrorAction Stop
        Write-Log "OpenAI endpoint validated successfully"
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 429) {
            Write-Log "OpenAI endpoint reachable (rate limited - normal for S0 tier)"
        } else {
            Write-Log "OpenAI endpoint returned HTTP $statusCode. Deployment will continue but check your endpoint/key." "WARN"
        }
    }
}

# =============================================================================
# Get User Inputs
# =============================================================================
function Get-DeploymentInputs {
    Write-Host ""
    Write-Log "Molten Deployment Configuration"
    Write-Host "================================"
    Write-Host ""
    Write-Host "Do you already have an Azure OpenAI resource, or should this script create one?"
    Write-Host "  1) I already have an endpoint and API key"
    Write-Host "  2) Create a new Azure OpenAI resource for me (auto)"
    $openaiChoice = Read-Host "Choice [1]"
    if (-not $openaiChoice) { $openaiChoice = "1" }
    
    if ($openaiChoice -eq "2") {
        $script:AutoCreateOpenAI = $true
        Write-Log "Will auto-create Azure OpenAI resource after resource group is created."
    } else {
        $script:AutoCreateOpenAI = $false
        $script:AzureOpenAIEndpoint = Read-Host "Azure OpenAI Endpoint URL"
        $script:AzureOpenAIApiKey = Read-Host "Azure OpenAI API Key" -AsSecureString
        $script:AzureOpenAIApiKeyPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:AzureOpenAIApiKey))
        
        $deploymentInput = Read-Host "Azure OpenAI Deployment Name [gpt-4o-mini]"
        $script:AzureOpenAIDeployment = if ($deploymentInput) { $deploymentInput } else { "gpt-4o-mini" }
    }
    
    $script:TelegramBotToken = Read-Host "Telegram Bot Token (optional - get one from @BotFather on Telegram)"
    
    Write-Host ""
    Write-Log "Configuration:"
    Write-Host "  Resource Group: $ResourceGroup"
    Write-Host "  Location: $Location"
    if ($script:AutoCreateOpenAI) {
        Write-Host "  OpenAI: Will be auto-created"
    } else {
        Write-Host "  OpenAI Endpoint: $($script:AzureOpenAIEndpoint)"
        Write-Host "  OpenAI Deployment: $($script:AzureOpenAIDeployment)"
    }
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
# Deploy Function App Code
# =============================================================================
function Publish-FunctionCode {
    $funcAppName = "$ProjectName-$Environment-func"
    
    if (-not (Get-Command "func" -ErrorAction SilentlyContinue)) {
        Write-Log "Azure Functions Core Tools not installed - skipping Function App code deployment." "WARN"
        Write-Log "Deploy manually: cd src/functions; npm install; npm run build; func azure functionapp publish $funcAppName" "WARN"
        return
    }
    
    Write-Log "Deploying Function App code to $funcAppName..."
    $origDir = Get-Location
    Set-Location src/functions
    npm install --production
    npm run build
    func azure functionapp publish $funcAppName --nozip
    Set-Location $origDir
    Write-Log "Function App code deployed"
}

# =============================================================================
# Register Telegram Webhook
# =============================================================================
function Register-TelegramWebhook {
    if (-not $script:TelegramBotToken) {
        Write-Log "No Telegram bot token provided - skipping webhook registration." "WARN"
        Write-Log "Set it later: Invoke-RestMethod -Method Post -Uri 'https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://$ProjectName-$Environment-func.azurewebsites.net/api/telegram'" "WARN"
        return
    }
    
    $funcAppName = "$ProjectName-$Environment-func"
    $webhookUrl = "https://$funcAppName.azurewebsites.net/api/telegram"
    
    Write-Log "Registering Telegram webhook: $webhookUrl"
    try {
        $response = Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$($script:TelegramBotToken)/setWebhook?url=$webhookUrl"
        if ($response.ok) {
            Write-Log "Telegram webhook registered successfully"
        } else {
            Write-Log "Telegram webhook registration response: $($response | ConvertTo-Json)" "WARN"
        }
    } catch {
        Write-Log "Telegram webhook registration failed: $($_.Exception.Message)" "WARN"
        Write-Log "Retry manually: Invoke-RestMethod -Method Post -Uri 'https://api.telegram.org/bot<TOKEN>/setWebhook?url=$webhookUrl'" "WARN"
    }
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
    Write-Host "Verify your bot:"
    Write-Host "  1. Open Telegram and find your bot by username"
    Write-Host "  2. Send: Hello!"
    Write-Host "  3. Check logs if no response: az containerapp logs show -n $ProjectName-$Environment-agent -g $ResourceGroup --tail 20"
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

# Auto-create Azure OpenAI if requested
if ($script:AutoCreateOpenAI) {
    New-OpenAIResource
}

# Validate OpenAI before proceeding
Test-OpenAIEndpoint

New-StorageAccount
New-KeyVault
New-MonitoringResources
New-FunctionApp
New-ContainerApp
Publish-FunctionCode
Register-TelegramWebhook
Write-Summary
