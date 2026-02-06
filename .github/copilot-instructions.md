# Project Guidelines

Molten (MoltBot) is a self-hosted Azure AI agent providing chat capabilities via Telegram, Slack, and Discord. Targets <$10/month using Azure free tiers. Optional integration with [OpenClaw](https://github.com/openclaw/openclaw) for enhanced skills and multi-channel support.

## Architecture

- **Azure Functions** (src/functions/) - Webhook receivers for platforms, JWT validation, queue dispatch
- **Agent** (src/agent/) - Express server + queue worker, LLM calls, skills execution
- **Skills** (src/agent/src/skills/) - TypeScript registry + Python subprocess executor
- **Integrations** (src/agent/src/integrations/) - Platform-specific message handlers
- **OpenClaw** (src/agent/src/openclaw/) - Optional Gateway client for enhanced AI capabilities

Data flow: Platform webhook → Functions → Storage Queue → Agent → [OpenClaw Gateway | Azure OpenAI] → Skills → Cache → Reply

## Build and Test

```bash
# Agent
cd src/agent && npm install && npm run build   # tsc compile
npm run dev                                      # ts-node-dev with respawn

# Functions  
cd src/functions && npm install && npm run build
npm run start                                    # func start locally
npm test                                         # jest

# Infrastructure
cd infra/terraform && terraform init && terraform apply
```

## Code Style

- TypeScript with strict mode, target ES2020, CommonJS modules
- Async/await throughout; early return pattern for validation
- Interface-first typing (see [types.ts](src/shared/types.ts))
- Console.log/warn/error for structured logging to App Insights
- Module-level caching for Azure SDK clients and secrets

## Project Conventions

- **Secrets**: Always via Key Vault + Managed Identity, never in code. Use `@Microsoft.KeyVault(...)` syntax in app settings
- **Authentication**: `DefaultAzureCredential` for all Azure service-to-service auth
- **Response caching**: LLM responses cached with 5-min TTL in [cache.ts](src/agent/src/utils/cache.ts)
- **Skills execution**: Python subprocess with JSON I/O, not SDK calls (see [anthropic_executor.py](src/agent/src/skills/anthropic_executor.py))
- **Token caps**: max_tokens=512 in LLM calls to bound costs

## OpenClaw Integration

Optional integration with OpenClaw Gateway for enhanced capabilities:
- **Skills**: Full ClawHub registry with bash, text_editor, browser, canvas
- **Channels**: WhatsApp, Signal, iMessage, Microsoft Teams (in addition to Telegram/Slack/Discord)
- **Models**: Anthropic Claude, OpenAI, and any OpenClaw-supported model

OpenClaw runs as a Container App in Azure (not locally). Enable via Terraform:
```bash
enable_openclaw = true
openclaw_model  = "anthropic/claude-sonnet-4-20250514"
```

See [openclaw/gateway-client.ts](src/agent/src/openclaw/gateway-client.ts) for implementation.

## Security

- Prompt injection detection in [safety.ts](src/agent/src/llm/safety.ts) - blocks patterns like "ignore previous instructions"
- Input limit: 4000 characters; output sanitization redacts long alphanumeric tokens
- Skills restricted to `/tmp` directory; dangerous commands blocked (rm -rf /, mkfs, fork bombs)
- 30-second timeout on skill execution
- TLS 1.2+ enforced; storage default-deny with Azure services bypass

## Deployment

Five options in deploy/: Terraform (recommended), Bicep, ARM, Azure CLI, PowerShell. Terraform variables in [terraform.tfvars.example](infra/terraform/terraform.tfvars.example).

## Prerequisites

- Azure CLI >= 2.50, Terraform >= 1.5, Node.js >= 20, Python >= 3.9
- Azure Functions Core Tools >= 4.x
- Azure OpenAI access + Telegram Bot Token
- (Optional) OpenClaw installed: `npm install -g openclaw@latest`
