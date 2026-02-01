# ARM Template Deployment

Deploy Molten using Azure Resource Manager (ARM) templates.

## Prerequisites

- Azure CLI or PowerShell with Az module
- Azure subscription
- Azure OpenAI access

## Quick Start

### 1. Configure Parameters

Edit `azuredeploy.parameters.json`:

```json
{
  "azureOpenAIEndpoint": {
    "value": "https://your-openai.openai.azure.com/"
  },
  "azureOpenAIApiKey": {
    "value": "your-api-key"
  }
}
```

### 2. Deploy with Azure CLI

```bash
# Create resource group
az group create --name molten-dev-rg --location westus3

# Deploy template
az deployment group create \
  --resource-group molten-dev-rg \
  --template-file azuredeploy.json \
  --parameters @azuredeploy.parameters.json
```

### 3. Deploy with PowerShell

```powershell
# Create resource group
New-AzResourceGroup -Name molten-dev-rg -Location westus3

# Deploy template
New-AzResourceGroupDeployment `
  -ResourceGroupName molten-dev-rg `
  -TemplateFile azuredeploy.json `
  -TemplateParameterFile azuredeploy.parameters.json
```

## Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|--------|
| projectName | Project name | No | molten |
| environment | Environment | No | dev |
| location | Azure region | No | westus3 |
| azureOpenAIEndpoint | OpenAI endpoint URL | Yes | - |
| azureOpenAIApiKey | OpenAI API key | Yes | - |
| azureOpenAIDeployment | Model deployment | No | gpt-4o-mini |
| telegramBotToken | Telegram token | No | - |

## Resources Deployed

- Storage Account (Standard LRS)
- Storage Queue (molten-work)
- Blob Container (molten-configs)
- Key Vault (Standard)
- Log Analytics Workspace
- Application Insights
- Function App (Consumption Y1)
- RBAC Role Assignments

## Outputs

After deployment, retrieve outputs:

```bash
# Azure CLI
az deployment group show \
  --resource-group molten-dev-rg \
  --name azuredeploy \
  --query properties.outputs
```

| Output | Description |
|--------|-------------|
| functionAppName | Name of the Function App |
| functionAppUrl | Base URL of the Function App |
| telegramWebhookUrl | URL for Telegram webhook |
| keyVaultName | Name of Key Vault |
| storageAccountName | Name of Storage Account |

## Post-Deployment

1. Deploy Function code:
   ```bash
   cd src/functions
   npm install && npm run build
   func azure functionapp publish molten-dev-func
   ```

2. Set Telegram webhook:
   ```bash
   curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://molten-dev-func.azurewebsites.net/api/telegram"
   ```

## Cleanup

```bash
az group delete --name molten-dev-rg --yes --no-wait
```

## Deploy to Azure Button

To add a "Deploy to Azure" button to your repository:

```markdown
[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FYOUR_USERNAME%2Fmolten%2Fmain%2Fdeploy%2Farm%2Fazuredeploy.json)
```
