# Getting Started with Molten

This guide walks you through everything needed to deploy Molten — from zero to a working AI bot in your Telegram.

## Step 1: Azure Account

1. **Create a free Azure account** (if you don't have one): [azure.microsoft.com/free](https://azure.microsoft.com/free/)
2. You get $200 credit for 30 days + always-free services. Molten uses only free-tier resources (except Azure OpenAI tokens).

## Step 2: Request Azure OpenAI Access

Azure OpenAI requires a one-time access application:

1. Go to [https://aka.ms/oai/access](https://aka.ms/oai/access)
2. Fill out the form with your Azure subscription ID
3. Approval typically takes **1–3 business days** (sometimes instant for pay-as-you-go subscriptions)
4. You'll get an email when approved

> **Note**: You can start deploying infrastructure while waiting for approval. The bot just won't respond until OpenAI is configured.

## Step 3: Create Azure OpenAI Resource + Model

Once approved, create your OpenAI resource:

### Option A: Via Azure Portal (Easiest)

1. Go to [Azure Portal](https://portal.azure.com) → **Create a resource** → search **"Azure OpenAI"**
2. Create with these settings:
   - **Name**: `molten-dev-openai` (or anything you like)
   - **Region**: `westus3` (or any region with GPT-4o-mini availability)
   - **Pricing tier**: `S0` (only option)
3. After creation, go to the resource → **Keys and Endpoint**:
   - Copy the **Endpoint** (e.g., `https://molten-dev-openai.openai.azure.com/`)
   - Copy **Key 1**
4. Go to **Model Deployments** → **Manage Deployments** → **Create**:
   - **Model**: `gpt-4o-mini`
   - **Deployment name**: `gpt-4o-mini` (keep it simple)
   - **Tokens per Minute**: `10K` (free tier is fine)

### Option B: Via Azure CLI

```bash
# Create the Cognitive Services account
az cognitiveservices account create \
  --name molten-dev-openai \
  --resource-group molten-dev-rg \
  --kind OpenAI \
  --sku S0 \
  --location westus3

# Deploy the model
az cognitiveservices account deployment create \
  --name molten-dev-openai \
  --resource-group molten-dev-rg \
  --deployment-name gpt-4o-mini \
  --model-name gpt-4o-mini \
  --model-version "2024-07-18" \
  --model-format OpenAI \
  --sku-capacity 10 \
  --sku-name Standard

# Get your endpoint and key
az cognitiveservices account show \
  --name molten-dev-openai \
  --resource-group molten-dev-rg \
  --query properties.endpoint -o tsv

az cognitiveservices account keys list \
  --name molten-dev-openai \
  --resource-group molten-dev-rg \
  --query key1 -o tsv
```

### Option C: Let the Deploy Script Do It

The Azure CLI deploy scripts (`deploy/azure-cli/deploy.sh` or `deploy.ps1`) can **auto-create** the Azure OpenAI resource and model for you. Just choose "auto" when prompted. See [deploy/azure-cli/README.md](../deploy/azure-cli/README.md).

> **Save these values** — you'll need them during deployment:
> - **Endpoint URL**: `https://<name>.openai.azure.com/`
> - **API Key**: (a long alphanumeric string)
> - **Deployment Name**: `gpt-4o-mini`

## Step 4: Create a Telegram Bot

1. Open Telegram and search for [@BotFather](https://t.me/botfather)
2. Send `/newbot`
3. Follow the prompts:
   - **Bot name**: `Molten AI` (display name, anything you want)
   - **Bot username**: `molten_ai_bot` (must end in `bot`, must be unique)
4. BotFather replies with your **Bot Token** — looks like `7123456789:AAH...` — **save this!**

> **Security**: Never share your bot token publicly or commit it to git. The deploy scripts store it securely in Azure Key Vault.

## Step 5: Install Required Tools

Install these on your local machine:

| Tool | Version | Install |
|------|---------|---------|
| **Azure CLI** | >= 2.50 | [Install guide](https://docs.microsoft.com/cli/azure/install-azure-cli) |
| **Node.js** | >= 20 LTS | [nodejs.org](https://nodejs.org/) |
| **Terraform** | >= 1.5 | [terraform.io/downloads](https://www.terraform.io/downloads) (if using Terraform) |
| **Azure Functions Core Tools** | >= 4.x | [Install guide](https://docs.microsoft.com/azure/azure-functions/functions-run-local) |
| **Docker** | Latest | [docker.com](https://www.docker.com/) (for building agent container) |
| **Python** | >= 3.9 | [python.org](https://www.python.org/) (for Anthropic skills) |

Verify installations:

```bash
az --version          # Azure CLI 2.50+
node --version        # v20.x or v22.x
terraform --version   # v1.5+ (Terraform only)
func --version        # 4.x
docker --version      # Docker Engine
python3 --version     # 3.9+
```

## Step 6: Deploy

### Option A: Terraform (Recommended)

Best for: Full infrastructure-as-code with state management and plan/apply workflow.

```bash
git clone https://github.com/kimvaddi/molten.git
cd molten

az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"

cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — fill in your AOAI endpoint, key, Telegram token, etc.

terraform init
terraform plan     # Review what will be created
terraform apply    # Type 'yes' to confirm
```

After Terraform finishes, deploy the Function App code and agent container:

```bash
# Deploy Functions
cd ../../src/functions
npm install && npm run build
func azure functionapp publish $(terraform -chdir=../../infra/terraform output -raw function_app_name)

# Build and push agent container (if using ACR)
cd ../agent
az acr build --registry <your-acr-name> --image moltbot-agent:latest --file Dockerfile .
```

### Option B: Azure CLI Script (One-Command)

Best for: Quick setup without Terraform. The script auto-creates everything including optional Azure OpenAI resource.

**Bash (Linux/macOS/WSL):**
```bash
git clone https://github.com/kimvaddi/molten.git
cd molten

az login
chmod +x deploy/azure-cli/deploy.sh
./deploy/azure-cli/deploy.sh
```

**PowerShell (Windows):**
```powershell
git clone https://github.com/kimvaddi/molten.git
cd molten

az login
.\deploy\azure-cli\deploy.ps1
```

The script will interactively prompt for all required values and deploy everything.

### Option C: ARM / Bicep (Infrastructure Only)

ARM and Bicep deploy **infrastructure only** (storage, key vault, functions, monitoring). They do **not** deploy the Agent Container App, function code, or register the Telegram webhook. Use these if you want to manage infrastructure separately.

See: [deploy/arm/README.md](../deploy/arm/README.md) | [deploy/bicep/README.md](../deploy/bicep/README.md)

## Step 7: Verify It Works

1. **Check Azure resources** were created:
   ```bash
   az resource list --resource-group molten-dev-rg --output table
   ```

2. **Check the Function App** is running:
   ```bash
   curl https://molten-dev-func.azurewebsites.net/api/telegram
   # Should return 400 or 401 (no token) — means it's running
   ```

3. **Send a test message** to your Telegram bot:
   - Open Telegram, find your bot by username
   - Send: `Hello!`
   - The bot should respond within a few seconds

4. **Check logs** if something isn't working:
   ```bash
   # Function App logs
   az webapp log tail --name molten-dev-func --resource-group molten-dev-rg

   # Container App logs
   az containerapp logs show --name molten-dev-agent --resource-group molten-dev-rg --tail 20
   ```

## Step 8: Optional Enhancements

| Feature | How to Enable |
|---------|---------------|
| **Slack integration** | Create Slack App → add bot token to Key Vault → configure webhook |
| **Discord integration** | Create Discord Application → add bot token → configure webhook |
| **Tavily web search** | Sign up at [tavily.com](https://tavily.com/) → add API key to Key Vault |
| **OpenClaw** | Set `enable_openclaw = true` in terraform.tfvars (Terraform only) |

## Troubleshooting

| Problem | Solution |
|---------|----------|
| **"Not authorized to access Azure OpenAI"** | Your AOAI access request hasn't been approved yet. Check email or re-apply at [aka.ms/oai/access](https://aka.ms/oai/access) |
| **Bot doesn't respond** | Check that the Telegram webhook is set: `curl https://api.telegram.org/bot<TOKEN>/getWebhookInfo` |
| **Function App 500 errors** | Check Application Insights for exceptions: Azure Portal → App Insights → Failures |
| **Container App not starting** | Check container logs: `az containerapp logs show --name molten-dev-agent --resource-group molten-dev-rg` |
| **Key Vault access denied** | RBAC propagation can take 30–60 seconds. Wait and retry. |
| **429 rate limit errors** | Normal on S0 tier. The agent has built-in exponential backoff with retry. |
| **Terraform state lock** | Run `terraform force-unlock <LOCK_ID>` if a previous run was interrupted |

## Cost Summary

| Service | Monthly Cost |
|---------|-------------|
| Azure Functions | **$0.00** (free tier) |
| Container Apps | **$0.00** (free tier) |
| Storage | **~$0.50** |
| Key Vault | **~$0.03** |
| App Insights | **$0.00** (5GB free) |
| Azure OpenAI (GPT-4o-mini) | **~$7.50** (~500K tokens) |
| **Total** | **~$8/month** |

See [docs/COST.md](COST.md) for optimization strategies.
