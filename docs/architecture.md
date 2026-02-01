# Molten - Azure Architecture

## Overview

Molten is a serverless AI agent running on Azure's free tier, optimized for cost efficiency (<$5/month).

**Region**: West US 3  
**License**: MIT

## High-Level Architecture

```
┌─────────────────┐                    ┌────────────────────────────────────────────┐
│   Telegram /    │      HTTPS         │     Azure Functions (Consumption Tier)     │
│   Slack /       │◄──────────────────►│     • HTTP Triggers for webhooks           │
│   Discord       │    Webhook         │     • Azure OpenAI integration             │
└─────────────────┘                    │     • Response caching                     │
                                       │     • Content safety filtering             │
                                       └──────────────────┬─────────────────────────┘
                                                          │
                    ┌─────────────────────────────────────┼─────────────────────────────────────┐
                    │                                     │                                     │
                    ▼                                     ▼                                     ▼
     ┌─────────────────────────┐       ┌─────────────────────────┐       ┌─────────────────────────┐
     │   Azure Key Vault       │       │   Azure Storage         │       │   Azure OpenAI          │
     │   • Bot tokens          │       │   • Blob: sessions      │       │   • GPT-4o-mini         │
     │   • API keys            │       │   • Table: metadata     │       │   • Pay-as-you-go       │
     │   • Managed Identity    │       │   • Queue: async work   │       │   • Token caps          │
     └─────────────────────────┘       └─────────────────────────┘       └─────────────────────────┘
                                                          │
                                                          ▼
                                       ┌─────────────────────────────────────────────┐
                                       │   Application Insights + Log Analytics      │
                                       │   • Request tracing                         │
                                       │   • Error monitoring                        │
                                       │   • Cost tracking                           │
                                       └─────────────────────────────────────────────┘
```

## Components

### Azure Functions (Primary Compute)
- **Purpose**: Handle all webhook requests and AI processing
- **SKU**: Consumption (Y1) - **FREE**: 1M executions/month
- **Runtime**: Node.js 20
- **Triggers**:
  - `HttpTelegram` - Telegram bot webhook
  - `HttpSlack` - Slack events webhook  
  - `HttpDiscord` - Discord interactions
  - `HttpAdmin` - Admin API endpoints
- **Responsibilities**:
  - Validate incoming requests
  - Content safety pre-filtering
  - Call Azure OpenAI for responses
  - Response caching
  - Send replies to messaging platforms

### Azure Storage
- **Purpose**: State persistence and async processing
- **SKU**: Standard LRS - **FREE**: 5GB/month
- **Components**:
  - **Blob**: Session data, configs, user preferences
  - **Table**: Conversation metadata, usage tracking
  - **Queue**: Async work items (optional, for background tasks)

### Azure Key Vault
- **Purpose**: Secrets management
- **SKU**: Standard - **FREE**: 10K operations/month
- **Secrets Stored**:
  - `azure-openai-endpoint` - OpenAI service endpoint
  - `azure-openai-api-key` - OpenAI API key
  - `telegram-bot-token` - Telegram bot token
  - `tavily-api-key` - Web search API (optional)
- **Access**: Managed Identity only (no keys in code)

### Azure OpenAI
- **Purpose**: LLM inference
- **Model**: GPT-4o-mini (cost-optimized)
- **Pricing**: Pay-per-token (~$0.15/1M input, ~$0.60/1M output)
- **Features**:
  - Response caching (50-80% savings)
  - Token caps (512 max)
  - Content safety filters

### Log Analytics + Application Insights
- **Purpose**: Observability
- **SKU**: Free tier - 5GB/month ingestion
- **Features**:
  - Request tracing
  - Error monitoring
  - Token usage tracking
  - Cost analysis

## Security Architecture

| Layer | Implementation |
|-------|----------------|
| **Authentication** | Entra ID + Managed Identity |
| **Secrets** | Key Vault (no secrets in code) |
| **Transport** | HTTPS-only, TLS 1.2+ |
| **Access Control** | Azure RBAC, least-privilege |
| **Content Safety** | Pre-flight prompt filtering |
| **Network** | Azure backbone (no public secrets) |

## Data Flow

1. **User sends message** → Telegram/Slack/Discord
2. **Platform webhook** → Azure Functions HTTP trigger
3. **Function validates** → JWT/signature verification
4. **Secrets fetched** → Key Vault via Managed Identity
5. **Check cache** → Return cached response if hit
6. **Call OpenAI** → GPT-4o-mini with safety filters
7. **Cache response** → Store for future hits
8. **Send reply** → Back to messaging platform
9. **Log telemetry** → Application Insights

## Cost Optimization

| Strategy | Implementation | Savings |
|----------|---------------|---------|
| Consumption tier | Pay only when executing | ~$0/mo idle |
| GPT-4o-mini | 10x cheaper than GPT-4 | ~90% on tokens |
| Response cache | In-memory + blob cache | 50-80% fewer API calls |
| Token caps | max_tokens=512 | Bounded per-request |
| Free tiers | All services use free SKUs | ~$0 infrastructure |
| GHCR | GitHub Container Registry | -$5/mo vs ACR |

## Optional: Container Apps

Container Apps configuration is preserved but disabled by default. Enable it for:
- Long-running agent tasks
- Heavy compute workloads  
- Advanced orchestration needs

See `infra/terraform/main.tf` for the commented Container Apps resources.
