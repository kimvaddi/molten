# Molten - Azure AI Agent (Free-Tier Optimized)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Azure](https://img.shields.io/badge/Azure-0078D4?logo=microsoft-azure&logoColor=white)](https://azure.microsoft.com)
[![Terraform](https://img.shields.io/badge/Terraform-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)

A self-hosted personal AI agent running on Azure's free tier services — inspired by Cloudflare's Moltworker, forged for the Azure ecosystem.

![Architecture Diagram](docs/architecture-diagram.png)

## 🎯 Design Goals
- **Minimal cost**: <$3/month using Azure free tiers
- **Security-first**: Managed Identity, Key Vault, Entra ID, content safety
- **No Mac mini**: Fully cloud-hosted, no dedicated hardware
- **Production-ready**: CI/CD, observability, scale-to-zero

## 🏗️ Architecture

```
┌──────────────┐     HTTPS      ┌─────────────────────────────────────┐
│  Telegram /  │───────────────►│  Azure Functions (Consumption)      │
│  Slack /     │                │  • Webhook handlers                 │
│  Discord     │◄───────────────│  • JWT validation                   │
└──────────────┘    Response    │  • Azure OpenAI integration         │
                                └──────────────┬──────────────────────┘
                                               │
                                               ▼
                    ┌─────────────────────────────────────────────────┐
                    │              Azure Storage (Free Tier)          │
                    │  • Blob: configs, sessions, attachments         │
                    │  • Table: conversation metadata                 │
                    │  • Queue: async work dispatch (optional)        │
                    └──────────────┬──────────────────────────────────┘
                                   │
                    ┌──────────────┴──────────────┐
                    ▼                             ▼
         ┌─────────────────────┐       ┌─────────────────────┐
         │  Azure Key Vault    │       │  Azure OpenAI       │
         │  • Secrets mgmt     │       │  • GPT-4o-mini      │
         │  • Managed Identity │       │  • Response cache   │
         └─────────────────────┘       └─────────────────────┘
```

See [docs/architecture.md](docs/architecture.md) for detailed diagrams.

## 💰 Cost Breakdown (Target: <$5/month)

| Service | Free Tier | Estimated Usage | Est. Cost |
|---------|-----------|-----------------|----------|
| Azure Functions | 1M exec/month | ~10K | $0 |
| Azure Storage | 5GB blob + queue | ~100MB | $0 |
| Key Vault | 10K ops/month | ~1K | $0 |
| Log Analytics | 5GB/month | ~500MB | $0 |
| Azure OpenAI | Pay-per-token | GPT-4o-mini | ~$2-5 |
| **Total** | | | **$2-5/mo** |

> **Note**: Costs depend on usage. The response cache can reduce OpenAI costs by 50-80%.

## 📋 Prerequisites

- Azure subscription (free tier works)
- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) >= 2.50
- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [Node.js](https://nodejs.org/) >= 20 LTS
- [Azure Functions Core Tools](https://docs.microsoft.com/azure/azure-functions/functions-run-local) >= 4.x
- Telegram Bot Token (from [@BotFather](https://t.me/botfather))
- Azure OpenAI access (requires [application](https://aka.ms/oai/access))
- *(Optional)* [Tavily API key](https://tavily.com/) for web search

## 🚀 Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/YOUR_USERNAME/molten.git
cd molten
```

### 2. Azure login

```bash
az login
az account set --subscription "YOUR_SUBSCRIPTION_ID"
```

### 3. Deploy infrastructure

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

terraform init
terraform plan
terraform apply
```

### 4. Deploy Functions

```bash
cd src/functions
npm install
npm run build
func azure functionapp publish $(terraform -chdir=../../infra/terraform output -raw function_app_name)
```

### 5. Configure Telegram Bot

```bash
# Get your webhook URL
WEBHOOK_URL=$(terraform -chdir=infra/terraform output -raw telegram_webhook_url)

# Set Telegram webhook
curl -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/setWebhook?url=${WEBHOOK_URL}"
```

## 💡 Cost Optimization Strategies

| Strategy | Savings |
|----------|--------|
| Azure Functions Consumption tier | FREE: 1M executions/month |
| GPT-4o-mini (not GPT-4) | 10x cheaper tokens |
| Semantic response cache | 50-80% fewer API calls |
| `max_tokens=512` cap | Bounded per-request cost |
| Storage Queue (not Service Bus) | Free tier eligible |
| GitHub Container Registry | Free vs Azure ACR ($5/mo) |

## 🔒 Security

- **No secrets in code**: All via Key Vault + Managed Identity
- **Entra ID authentication**: For admin UI
- **Content safety filters**: Block harmful prompts/responses
- **HTTPS-only**: TLS 1.2+ enforced
- **RBAC**: Least-privilege access

See [docs/security-baseline.md](docs/security-baseline.md).

## 📁 Project Structure

```
molten/
├── infra/
│   └── terraform/           # Terraform IaC (primary)
├── deploy/
│   ├── azure-cli/           # Azure CLI scripts
│   ├── powershell/          # PowerShell deployment
│   ├── arm/                  # ARM templates
│   └── bicep/                # Bicep modules
├── src/
│   ├── functions/           # Azure Functions (webhooks + AI)
│   ├── agent/               # Agent runtime (Container Apps - optional)
│   └── shared/              # Shared utilities
├── docs/                     # Architecture & documentation
└── .github/workflows/        # CI/CD pipelines
```

## 🚀 Deployment Options

| Method | Description | Guide |
|--------|-------------|-------|
| **Terraform** | Infrastructure as Code (recommended) | [deploy/terraform](infra/terraform/) |
| **Azure CLI** | Shell scripts for Linux/macOS/WSL | [deploy/azure-cli](deploy/azure-cli/) |
| **PowerShell** | Native Windows deployment | [deploy/powershell](deploy/powershell/) |
| **ARM Templates** | Azure Resource Manager JSON | [deploy/arm](deploy/arm/) |
| **Bicep** | Azure DSL for ARM | [deploy/bicep](deploy/bicep/) |

## 🤝 Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) before submitting PRs.

## 📜 License

[MIT License](LICENSE) - see LICENSE file for details.

---

**Molten** - Forged in Azure 🔥
