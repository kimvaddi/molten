# PowerShell Deployment

Deploy Molten using the Azure PowerShell module (`Az`).

> **Note**: This script uses the **Az PowerShell module** (not Azure CLI). It deploys all infrastructure including the Agent Container App, but does **not** auto-deploy function code or register the Telegram webhook. For a fully automated one-command experience, see the [Azure CLI scripts](../azure-cli/) instead.

## Prerequisites

- Windows PowerShell 5.1+ or PowerShell Core 7+
- [Azure PowerShell Module](https://docs.microsoft.com/powershell/azure/install-az-ps)
- [Node.js](https://nodejs.org/) >= 20 LTS
- [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local) >= 4.x

### Install Azure PowerShell

```powershell
Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
```

## Quick Start

```powershell
Connect-AzAccount

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

## What Gets Deployed

| Resource | SKU | Purpose |
|----------|-----|----------|
| Resource Group | — | Container for all resources |
| Storage Account | Standard LRS | State and queue storage |
| Key Vault | Standard | Secrets management (RBAC) |
| Log Analytics | Free tier | Logging |
| Application Insights | Free tier | Monitoring |
| Function App | Consumption (Y1) | Webhook handlers |
| **Agent Container App** | Free tier | AI agent runtime |

## Post-Deployment

After infrastructure is deployed, you still need to:

1. **Deploy Function App code**:
   ```powershell
   Set-Location src/functions
   npm install
   npm run build
   func azure functionapp publish molten-dev-func
   ```

2. **Register Telegram webhook**:
   ```powershell
   $token = "YOUR_BOT_TOKEN"
   $url = "https://molten-dev-func.azurewebsites.net/api/telegram"
   Invoke-RestMethod -Method Post -Uri "https://api.telegram.org/bot$token/setWebhook?url=$url"
   ```

3. **Verify** — send a message to your Telegram bot.

## Cleanup

```powershell
Remove-AzResourceGroup -Name molten-dev-rg -Force -AsJob
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Module not found | Run `Update-Module -Name Az` |
| Key Vault access denied | Wait 30–60 seconds for RBAC propagation, then retry |
| Container App not starting | Check logs: `az containerapp logs show -n molten-dev-agent -g molten-dev-rg --tail 20` |
