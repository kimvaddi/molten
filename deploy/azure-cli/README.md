# Azure CLI Deployment

Deploy Molten using Azure CLI commands.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) >= 2.50
- Azure subscription
- Azure OpenAI access

## Quick Start

### Bash (Linux/macOS/WSL)

```bash
# Login to Azure
az login

# Run deployment script
chmod +x deploy.sh
./deploy.sh
```

### PowerShell (Windows)

```powershell
# Login to Azure
az login

# Run deployment script
.\deploy.ps1
```

## What Gets Deployed

| Resource | SKU | Purpose |
|----------|-----|----------|
| Resource Group | - | Container for all resources |
| Storage Account | Standard LRS | State and queue storage |
| Key Vault | Standard | Secrets management |
| Log Analytics | Free tier | Logging |
| Application Insights | Free tier | Monitoring |
| Function App | Consumption (Y1) | Webhook handlers + AI |

## Configuration

The script will prompt for:

| Parameter | Description | Required |
|-----------|-------------|----------|
| Azure OpenAI Endpoint | Your Azure OpenAI endpoint URL | Yes |
| Azure OpenAI API Key | API key for Azure OpenAI | Yes |
| Azure OpenAI Deployment | Model deployment name | No (default: gpt-4o-mini) |
| Telegram Bot Token | From @BotFather | No |

## Customization

Edit the configuration variables at the top of the script:

```bash
PROJECT_NAME="molten"
ENVIRONMENT="dev"
LOCATION="westus3"
```

## Post-Deployment

1. Deploy Function code:
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
