# Bicep Deployment

Deploy Molten infrastructure using Azure Bicep — a declarative language for Azure resources.

> **Note**: Bicep templates deploy **infrastructure only** (storage, key vault, functions, monitoring). They do **not** create the Agent Container App, deploy function code, or register the Telegram webhook. For a one-command deployment, use the [Azure CLI scripts](../azure-cli/) instead.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) >= 2.50 (includes Bicep)
- Or [Bicep CLI](https://docs.microsoft.com/azure/azure-resource-manager/bicep/install) standalone
- Azure subscription
- Azure OpenAI access

## Quick Start

### 1. Login to Azure

```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### 2. Create Resource Group

```bash
az group create --name molten-dev-rg --location westus3
```

### 3. Deploy

```bash
az deployment group create \
  --resource-group molten-dev-rg \
  --template-file main.bicep \
  --parameters \
    azureOpenAIEndpoint='https://your-openai.openai.azure.com/' \
    azureOpenAIApiKey='your-api-key'
```

### With Parameter File

Create `main.bicepparam`:

```bicep
using 'main.bicep'

param projectName = 'molten'
param environment = 'dev'
param location = 'westus3'
param azureOpenAIEndpoint = 'https://your-openai.openai.azure.com/'
param azureOpenAIApiKey = 'your-api-key'
param azureOpenAIDeployment = 'gpt-4o-mini'
```

Deploy:

```bash
az deployment group create \
  --resource-group molten-dev-rg \
  --template-file main.bicep \
  --parameters main.bicepparam
```

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| projectName | string | No | molten | Project name for resources |
| environment | string | No | dev | Environment (dev/staging/prod) |
| location | string | No | westus3 | Azure region |
| azureOpenAIEndpoint | securestring | Yes | - | OpenAI endpoint URL |
| azureOpenAIApiKey | securestring | Yes | - | OpenAI API key |
| azureOpenAIDeployment | string | No | gpt-4o-mini | Model deployment name |
| telegramBotToken | securestring | No | - | Telegram bot token |

## Resources Deployed

| Resource | SKU | Free Tier |
|----------|-----|----------|
| Storage Account | Standard LRS | 5GB included |
| Key Vault | Standard | 10K ops/month |
| Log Analytics | PerGB2018 | 5GB/month |
| Application Insights | Workspace-based | Included |
| Function App | Consumption (Y1) | 1M exec/month |

## Outputs

After deployment:

```bash
az deployment group show \
  --resource-group molten-dev-rg \
  --name main \
  --query properties.outputs
```

| Output | Description |
|--------|-------------|
| functionAppName | Function App name |
| functionAppUrl | Base URL |
| telegramWebhookUrl | Telegram webhook endpoint |
| slackWebhookUrl | Slack webhook endpoint |
| discordWebhookUrl | Discord webhook endpoint |
| keyVaultName | Key Vault name |
| keyVaultUri | Key Vault URI |
| storageAccountName | Storage Account name |

## Modular Structure

For larger deployments, split into modules:

```
bicep/
├── main.bicep           # Main template
├── main.bicepparam      # Parameters
└── modules/
    ├── storage.bicep    # Storage resources
    ├── keyvault.bicep   # Key Vault
    ├── monitoring.bicep # Log Analytics + App Insights
    └── function.bicep   # Function App
```

## What-If Deployment

Preview changes before deploying:

```bash
az deployment group what-if \
  --resource-group molten-dev-rg \
  --template-file main.bicep \
  --parameters azureOpenAIEndpoint='...' azureOpenAIApiKey='...'
```

## Post-Deployment

1. Deploy Functions code:
   ```bash
   cd src/functions
   npm install && npm run build
   func azure functionapp publish molten-dev-func
   ```

2. Configure Telegram webhook:
   ```bash
   curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook?url=https://molten-dev-func.azurewebsites.net/api/telegram"
   ```

## Cleanup

```bash
az group delete --name molten-dev-rg --yes --no-wait
```

## Bicep vs ARM

| Feature | Bicep | ARM JSON |
|---------|-------|----------|
| Syntax | Declarative DSL | JSON |
| Readability | High | Low |
| Modules | Native support | Linked templates |
| Type safety | Built-in | Limited |
| Tooling | VS Code extension | Generic JSON |

Bicep compiles to ARM JSON, so both are equivalent at deployment time.
