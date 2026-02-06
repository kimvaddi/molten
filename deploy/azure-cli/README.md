# Azure CLI Deployment

Deploy Molten using interactive Azure CLI scripts. These scripts handle **everything** — infrastructure, code deployment, and webhook registration — in a single run.

## What the Script Does

1. **Checks prerequisites** — Azure CLI, Node.js (v20+), and optionally Docker & Azure Functions Core Tools
2. **Prompts for configuration** — OpenAI endpoint/key (or auto-creates an Azure OpenAI resource), Telegram bot token
3. **Validates OpenAI** — Pre-flight HTTP check against your endpoint before deploying
4. **Creates all infrastructure** — Resource group, storage, Key Vault, monitoring, Function App, Agent Container App
5. **Deploys Function App code** — Automatically runs `npm install`, `npm run build`, `func publish` (if `func` is installed)
6. **Registers Telegram webhook** — Automatically calls the Telegram API to set your webhook URL (if token provided)

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) >= 2.50
- [Node.js](https://nodejs.org/) >= 20 LTS
- Azure subscription
- *(Recommended)* [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local) >= 4.x — for auto-deploying function code
- *(Optional)* [Docker](https://www.docker.com/) — for building agent container locally

> **Don't have Azure OpenAI yet?** The script can auto-create the resource and deploy the gpt-4o-mini model for you. Just choose option 2 when prompted.

## Quick Start

### Bash (Linux/macOS/WSL)

```bash
az login
git clone https://github.com/kimvaddi/molten.git
cd molten

chmod +x deploy/azure-cli/deploy.sh
./deploy/azure-cli/deploy.sh
```

### PowerShell (Windows)

```powershell
az login
git clone https://github.com/kimvaddi/molten.git
cd molten

.\deploy\azure-cli\deploy.ps1
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
| **Agent Container App** | Free tier | AI agent runtime (Node.js 22) |
| *(Optional)* Azure OpenAI | S0 | GPT-4o-mini (auto-created if requested) |

## Configuration

The script will interactively prompt for:

| Parameter | Description | Required |
|-----------|-------------|----------|
| OpenAI Setup | Use existing endpoint or auto-create | Yes |
| Azure OpenAI Endpoint | Your Azure OpenAI endpoint URL | If manual |
| Azure OpenAI API Key | API key for Azure OpenAI | If manual |
| Azure OpenAI Deployment | Model deployment name | No (default: gpt-4o-mini) |
| Telegram Bot Token | From [@BotFather](https://t.me/botfather) | No (webhook skipped if empty) |

## Customization

Edit the configuration variables at the top of the script:

```bash
PROJECT_NAME="molten"
ENVIRONMENT="dev"
LOCATION="westus3"
```

## Cleanup

```bash
az group delete --name molten-dev-rg --yes --no-wait
```
