<#
.SYNOPSIS
    Deploys Molten infrastructure to Azure using Azure PowerShell module.

.DESCRIPTION
    This script deploys the complete Molten infrastructure including:
    - Resource Group
    - Storage Account with Queue and Blob
    - Key Vault with secrets
    - Log Analytics Workspace
    - Application Insights
    - Azure Function App (Consumption tier)
    - Container Apps Environment + Agent Container App

.PARAMETER ProjectName
    Name of the project (default: molten)

.PARAMETER Environment
    Environment name (default: dev)

.PARAMETER Location
    Azure region (default: westus3)

.PARAMETER AzureOpenAIEndpoint
    Azure OpenAI endpoint URL

.PARAMETER AzureOpenAIDeployment
    Azure OpenAI model deployment name (default: gpt-4o-mini)

.EXAMPLE
    .\Deploy-Molten.ps1 -AzureOpenAIEndpoint "https://myopenai.openai.azure.com/"

.NOTES
    Author: Molten Contributors
    License: MIT
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$ProjectName = "molten",
    
    [Parameter()]
    [string]$Environment = "dev",
    
    [Parameter()]
    [string]$Location = "westus3",
    
    [Parameter()]
    [string]$AzureOpenAIEndpoint,
    
    [Parameter()]
    [string]$AzureOpenAIDeployment = "gpt-4o-mini"
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

# =============================================================================
# Configuration
# =============================================================================
$ResourceGroupName = "$ProjectName-$Environment-rg"
$StorageAccountName = "$ProjectName$($Environment)stor"
$KeyVaultName = "$ProjectName-$Environment-kv"
$LogAnalyticsName = "$ProjectName-$Environment-logs"
$AppInsightsName = "$ProjectName-$Environment-insights"
$FunctionPlanName = "$ProjectName-$Environment-func-plan"
$FunctionAppName = "$ProjectName-$Environment-func"
$CAEName = "$ProjectName-$Environment-cae"
$AgentAppName = "$ProjectName-$Environment-agent"

$Tags = @{
    Project = $ProjectName
    Environment = $Environment
    ManagedBy = "PowerShell"
}

# =============================================================================
# Helper Functions
# =============================================================================
function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

# =============================================================================
# Prerequisites Check
# =============================================================================
function Test-Prerequisites {
    Write-Step "Checking prerequisites"
    
    # Check Azure PowerShell module
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        Write-Fail "Azure PowerShell module not found. Install with: Install-Module -Name Az -Scope CurrentUser"
        exit 1
    }
    
    # Check if logged in
    $context = Get-AzContext
    if (-not $context) {
        Write-Host "Not logged in to Azure. Running Connect-AzAccount..." -ForegroundColor Yellow
        Connect-AzAccount
    }
    
    $context = Get-AzContext
    Write-Success "Logged in as: $($context.Account.Id)"
    Write-Success "Subscription: $($context.Subscription.Name)"
}

# =============================================================================
# Get User Inputs
# =============================================================================
function Get-DeploymentInputs {
    Write-Step "Deployment Configuration"
    
    if (-not $script:AzureOpenAIEndpoint) {
        $script:AzureOpenAIEndpoint = Read-Host "Azure OpenAI Endpoint URL"
    }
    
    $script:AzureOpenAIApiKey = Read-Host "Azure OpenAI API Key" -AsSecureString
    $script:TelegramBotToken = Read-Host "Telegram Bot Token (optional, press Enter to skip)"
    
    Write-Host ""
    Write-Host "Configuration Summary:" -ForegroundColor Yellow
    Write-Host "  Resource Group: $ResourceGroupName"
    Write-Host "  Location: $Location"
    Write-Host "  OpenAI Endpoint: $($script:AzureOpenAIEndpoint)"
    Write-Host "  OpenAI Deployment: $AzureOpenAIDeployment"
}

# =============================================================================
# Create Resource Group
# =============================================================================
function New-MoltenResourceGroup {
    Write-Step "Creating Resource Group: $ResourceGroupName"
    
    $rg = New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Tag $Tags -Force
    Write-Success "Resource Group created: $($rg.ResourceId)"
    return $rg
}

# =============================================================================
# Create Storage Account
# =============================================================================
function New-MoltenStorageAccount {
    Write-Step "Creating Storage Account: $StorageAccountName"
    
    $storage = New-AzStorageAccount `
        -ResourceGroupName $ResourceGroupName `
        -Name $StorageAccountName `
        -Location $Location `
        -SkuName Standard_LRS `
        -Kind StorageV2 `
        -MinimumTlsVersion TLS1_2 `
        -AllowBlobPublicAccess $false `
        -Tag $Tags
    
    $ctx = $storage.Context
    
    # Create queue
    New-AzStorageQueue -Name "molten-work" -Context $ctx | Out-Null
    Write-Success "Storage queue created: molten-work"
    
    # Create blob container
    New-AzStorageContainer -Name "molten-configs" -Context $ctx -Permission Off | Out-Null
    Write-Success "Blob container created: molten-configs"
    
    Write-Success "Storage Account created: $StorageAccountName"
    return $storage
}

# =============================================================================
# Create Key Vault
# =============================================================================
function New-MoltenKeyVault {
    Write-Step "Creating Key Vault: $KeyVaultName"
    
    $kv = New-AzKeyVault `
        -VaultName $KeyVaultName `
        -ResourceGroupName $ResourceGroupName `
        -Location $Location `
        -EnableRbacAuthorization `
        -Sku Standard `
        -Tag $Tags
    
    # Get current user
    $currentUser = (Get-AzContext).Account.Id
    $currentUserObjectId = (Get-AzADUser -UserPrincipalName $currentUser).Id
    
    # Grant secrets access to current user
    New-AzRoleAssignment `
        -ObjectId $currentUserObjectId `
        -RoleDefinitionName "Key Vault Secrets Officer" `
        -Scope $kv.ResourceId | Out-Null
    
    Write-Host "Waiting for RBAC propagation (30 seconds)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 30
    
    # Add secrets
    $apiKeyPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($script:AzureOpenAIApiKey))
    
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "azure-openai-endpoint" `
        -SecretValue (ConvertTo-SecureString $script:AzureOpenAIEndpoint -AsPlainText -Force) | Out-Null
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "azure-openai-api-key" `
        -SecretValue (ConvertTo-SecureString $apiKeyPlain -AsPlainText -Force) | Out-Null
    
    if ($script:TelegramBotToken) {
        Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "telegram-bot-token" `
            -SecretValue (ConvertTo-SecureString $script:TelegramBotToken -AsPlainText -Force) | Out-Null
    }
    
    Write-Success "Key Vault created with secrets"
    return $kv
}

# =============================================================================
# Create Monitoring Resources
# =============================================================================
function New-MoltenMonitoring {
    Write-Step "Creating Log Analytics Workspace: $LogAnalyticsName"
    
    $logAnalytics = New-AzOperationalInsightsWorkspace `
        -ResourceGroupName $ResourceGroupName `
        -Name $LogAnalyticsName `
        -Location $Location `
        -Sku PerGB2018 `
        -RetentionInDays 30 `
        -Tag $Tags
    
    Write-Success "Log Analytics created"
    
    Write-Step "Creating Application Insights: $AppInsightsName"
    
    $appInsights = New-AzApplicationInsights `
        -ResourceGroupName $ResourceGroupName `
        -Name $AppInsightsName `
        -Location $Location `
        -WorkspaceResourceId $logAnalytics.ResourceId `
        -Kind web `
        -Tag $Tags
    
    Write-Success "Application Insights created"
    return $appInsights
}

# =============================================================================
# Create Function App
# =============================================================================
function New-MoltenFunctionApp {
    param($AppInsights, $Storage, $KeyVault)
    
    Write-Step "Creating Function App: $FunctionAppName"
    
    # Create consumption plan
    $plan = New-AzFunctionAppPlan `
        -ResourceGroupName $ResourceGroupName `
        -Name $FunctionPlanName `
        -Location $Location `
        -Sku Y1 `
        -WorkerType Linux
    
    Write-Success "Function App Plan created (Consumption tier)"
    
    # Create function app
    $funcApp = New-AzFunctionApp `
        -ResourceGroupName $ResourceGroupName `
        -Name $FunctionAppName `
        -PlanName $FunctionPlanName `
        -StorageAccountName $StorageAccountName `
        -Runtime node `
        -RuntimeVersion 20 `
        -FunctionsVersion 4 `
        -IdentityType SystemAssigned `
        -Tag $Tags
    
    # Grant Key Vault access
    $funcIdentity = $funcApp.IdentityPrincipalId
    New-AzRoleAssignment `
        -ObjectId $funcIdentity `
        -RoleDefinitionName "Key Vault Secrets User" `
        -Scope $KeyVault.ResourceId | Out-Null
    
    # Grant Storage access
    New-AzRoleAssignment `
        -ObjectId $funcIdentity `
        -RoleDefinitionName "Storage Queue Data Contributor" `
        -Scope $Storage.Id | Out-Null
    
    # Configure app settings
    $appSettings = @{
        "FUNCTIONS_WORKER_RUNTIME" = "node"
        "QUEUE_NAME" = "molten-work"
        "KEY_VAULT_URI" = $KeyVault.VaultUri
        "STORAGE_ACCOUNT_NAME" = $StorageAccountName
        "AZURE_OPENAI_DEPLOYMENT" = $AzureOpenAIDeployment
        "APPLICATIONINSIGHTS_CONNECTION_STRING" = $AppInsights.ConnectionString
    }
    
    Update-AzFunctionAppSetting `
        -ResourceGroupName $ResourceGroupName `
        -Name $FunctionAppName `
        -AppSetting $appSettings | Out-Null
    
    Write-Success "Function App created and configured"
    return $funcApp
}

# =============================================================================
# Create Agent Container App (uses az CLI for Container Apps)
# =============================================================================
function New-MoltenContainerApp {
    param($AppInsights, $Storage, $KeyVault)

    Write-Step "Creating Container Apps Environment: $CAEName"

    # Ensure containerapp extension is installed
    az extension add --name containerapp --upgrade --only-show-errors 2>$null

    $logCustomerId = (Get-AzOperationalInsightsWorkspace `
        -ResourceGroupName $ResourceGroupName `
        -Name $LogAnalyticsName).CustomerId

    $logKey = (Get-AzOperationalInsightsWorkspaceSharedKey `
        -ResourceGroupName $ResourceGroupName `
        -WorkspaceName $LogAnalyticsName).PrimarySharedKey

    az containerapp env create `
        --name $CAEName `
        --resource-group $ResourceGroupName `
        --location $Location `
        --logs-workspace-id $logCustomerId `
        --logs-workspace-key $logKey

    $agentImage = if ($env:AGENT_IMAGE) { $env:AGENT_IMAGE } else { "ghcr.io/kimvaddi/molten:latest" }

    Write-Step "Creating Agent Container App: $AgentAppName"

    az containerapp create `
        --name $AgentAppName `
        --resource-group $ResourceGroupName `
        --environment $CAEName `
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
            "STORAGE_ACCOUNT_NAME=$StorageAccountName" `
            "QUEUE_NAME=molten-work" `
            "KEY_VAULT_URI=$($KeyVault.VaultUri)" `
            "AZURE_OPENAI_DEPLOYMENT=$AzureOpenAIDeployment" `
            "APPLICATIONINSIGHTS_CONNECTION_STRING=$($AppInsights.ConnectionString)" `
            "PORT=8080"

    $agentPrincipalId = az containerapp identity show `
        --name $AgentAppName `
        --resource-group $ResourceGroupName `
        --query principalId -o tsv

    Write-Log "Granting Agent Managed Identity roles..."

    New-AzRoleAssignment -ObjectId $agentPrincipalId `
        -RoleDefinitionName "Key Vault Secrets User" `
        -Scope $KeyVault.ResourceId | Out-Null
    New-AzRoleAssignment -ObjectId $agentPrincipalId `
        -RoleDefinitionName "Storage Queue Data Contributor" `
        -Scope $Storage.Id | Out-Null
    New-AzRoleAssignment -ObjectId $agentPrincipalId `
        -RoleDefinitionName "Storage Blob Data Contributor" `
        -Scope $Storage.Id | Out-Null
    New-AzRoleAssignment -ObjectId $agentPrincipalId `
        -RoleDefinitionName "Storage Table Data Contributor" `
        -Scope $Storage.Id | Out-Null

    Write-Success "Agent Container App created with Managed Identity"
}

# =============================================================================
# Print Summary
# =============================================================================
function Write-DeploymentSummary {
    Write-Host ""
    Write-Host "=============================================================================" -ForegroundColor Green
    Write-Host "  DEPLOYMENT COMPLETE!" -ForegroundColor Green
    Write-Host "=============================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Resources Created:" -ForegroundColor Yellow
    Write-Host "  Resource Group:      $ResourceGroupName"
    Write-Host "  Function App:        $FunctionAppName"
    Write-Host "  Agent Container App: $AgentAppName"
    Write-Host "  Key Vault:          $KeyVaultName"
    Write-Host "  Storage Account:     $StorageAccountName"
    Write-Host "  Log Analytics:       $LogAnalyticsName"
    Write-Host "  Application Insights: $AppInsightsName"
    Write-Host ""
    Write-Host "Webhook URLs:" -ForegroundColor Yellow
    Write-Host "  Telegram: https://$FunctionAppName.azurewebsites.net/api/telegram"
    Write-Host "  Slack:    https://$FunctionAppName.azurewebsites.net/api/slack"
    Write-Host "  Discord:  https://$FunctionAppName.azurewebsites.net/api/discord"
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Deploy Function code:"
    Write-Host "     cd src/functions"
    Write-Host "     npm install && npm run build"
    Write-Host "     func azure functionapp publish $FunctionAppName"
    Write-Host ""
    Write-Host "  2. Build and push agent image:"
    Write-Host "     cd src/agent"
    Write-Host "     docker build -t ghcr.io/kimvaddi/molten:latest ."
    Write-Host "     docker push ghcr.io/kimvaddi/molten:latest"
    Write-Host "     az containerapp update -n $AgentAppName -g $ResourceGroupName --image ghcr.io/kimvaddi/molten:latest"
    Write-Host ""
    Write-Host "  3. Configure Telegram webhook:"
    Write-Host "     Invoke-RestMethod -Method Post -Uri `"https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://$FunctionAppName.azurewebsites.net/api/telegram`""
    Write-Host ""
}

# =============================================================================
# Main Deployment
# =============================================================================
function Start-Deployment {
    Write-Host ""
    Write-Host "=============================================================================" -ForegroundColor Cyan
    Write-Host "  Molten - Azure Deployment (PowerShell)" -ForegroundColor Cyan
    Write-Host "=============================================================================" -ForegroundColor Cyan
    
    Test-Prerequisites
    Get-DeploymentInputs
    
    Write-Host ""
    $confirm = Read-Host "Proceed with deployment? (y/N)"
    if ($confirm -notmatch "^[Yy]$") {
        Write-Host "Deployment cancelled." -ForegroundColor Yellow
        return
    }
    
    $rg = New-MoltenResourceGroup
    $storage = New-MoltenStorageAccount
    $kv = New-MoltenKeyVault
    $appInsights = New-MoltenMonitoring
    $funcApp = New-MoltenFunctionApp -AppInsights $appInsights -Storage $storage -KeyVault $kv
    New-MoltenContainerApp -AppInsights $appInsights -Storage $storage -KeyVault $kv
    
    Write-DeploymentSummary
}

# Run deployment
Start-Deployment
