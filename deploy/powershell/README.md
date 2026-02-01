# PowerShell Deployment

Deploy Molten using the Azure PowerShell module.

## Prerequisites

- Windows PowerShell 5.1+ or PowerShell Core 7+
- [Azure PowerShell Module](https://docs.microsoft.com/powershell/azure/install-az-ps)

### Install Azure PowerShell

```powershell
# Install from PowerShell Gallery
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
```

## Quick Start

```powershell
# Login to Azure
Connect-AzAccount

# Run deployment
.\Deploy-Molten.ps1
```

## Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-ProjectName` | Project name for resources | molten |
| `-Environment` | Environment (dev/prod) | dev |
| `-Location` | Azure region | westus3 |
| `-AzureOpenAIEndpoint` | OpenAI endpoint URL | (prompted) |
| `-AzureOpenAIDeployment` | Model deployment name | gpt-4o-mini |

## Examples

### Basic Deployment

```powershell
.\Deploy-Molten.ps1
```

### Production Deployment

```powershell
.\Deploy-Molten.ps1 `
    -ProjectName "molten" `
    -Environment "prod" `
    -Location "westus3" `
    -AzureOpenAIEndpoint "https://myopenai.openai.azure.com/"
```

## Post-Deployment

1. Deploy Functions:
   ```powershell
   Set-Location src/functions
   npm install
   npm run build
   func azure functionapp publish molten-dev-func
   ```

2. Configure Telegram:
   ```powershell
   $token = "YOUR_BOT_TOKEN"
   $url = "https://molten-dev-func.azurewebsites.net/api/telegram"
   Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$token/setWebhook?url=$url"
   ```

## Cleanup

```powershell
Remove-AzResourceGroup -Name molten-dev-rg -Force -AsJob
```

## Troubleshooting

### Module not found

```powershell
# Update Azure PowerShell
Update-Module -Name Az
```

### Permission denied for Key Vault

Wait 30-60 seconds for RBAC to propagate, then retry.
