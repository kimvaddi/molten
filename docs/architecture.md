# Molten - Azure Architecture

## Overview

Molten is a serverless AI agent running on Azure's free tier, optimized for cost efficiency (<$10/month).

**Region**: West US 3 (or your configured region)  
**License**: MIT  
**Runtime**: Node.js 22 (agent), Node.js 20 (functions)  
**LLM**: Azure OpenAI GPT-4o-mini with function-calling (tool use)

## High-Level Architecture

```
                                                          ┌──────────┐
                                                          │ Telegram │
                                                          └────┬─────┘
                                                          ┌────┴─────┐
                                                          │  Slack   │
                                                          └────┬─────┘
                                                          ┌────┴─────┐
                                                          │ Discord  │
                                                          └────┬─────┘
                                                               │ reply
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│ Agent Runtime (Container Apps Environment: molten-dev-cae)                                  │
│                                                                                             │
│  ┌──────────────┐    ┌─────────────────────────────────┐    ┌─────────────────────────────┐  │
│  │              │    │  molten-dev-agent                │    │  molten-dev-openclaw        │  │
│  │  Azure       │    │  Azure Container Apps            │───►│  OpenClaw Gateway           │  │
│  │  Key Vault   ├────│  Consumption, scale-to-zero      │    │  Internal ingress only      │  │
│  │              │    │                                  │    │  wss:// port 18789          │  │
│  └──────────────┘    └──────────┬───────────────────────┘    └──────────────┬──────────────┘  │
│                                 │      WebSocket (internal) wss://         │                  │
└─────────────────────────────────┼──────────────────────────────────────────┼──────────────────┘
                                  │                                         │
                     read/write   │   direct fallback                       │
┌──────────────────┐              │   (if Gateway down)   ┌─────────────────┼──────────────────┐
│ Serverless       │              │         ┌ ─ ─ ─ ─ ─ ─►│ LLM Backends    │                  │
│ Control Plane    │              │         ╎             │                 │                  │
│                  │              │         ╎             │  ┌──────────────┴───────────────┐  │
│ ┌──────────────┐ │              │         ╎             │  │  Azure OpenAI                │  │
│ │Storage Queue ├─┼──────────────┘         ╎             │  │  GPT-4o-mini (PAYG)          │  │
│ │(work dispatch)│ │                       ╎             │  │  Managed Identity            │  │
│ └──────────────┘ │              ┌─────────┘             │  └──────────────────────────────┘  │
│                  │              │                       │  ┌──────────────────────────────┐  │
│ ┌──────────────┐ │              │                       │  │  Azure API Management        │  │
│ │Azure Monitor │ │              │   when governance     │  │  AI Gateway (Optional)       │  │
│ │(Basic Logs)  │ │              │   needed              │  └──────────────────────────────┘  │
│ └──────────────┘ │              │  ─ ─ ─ ─ ─ ─ ─ ─ ─ ─►│                                    │
│                  │              │                       └────────────────────────────────────┘
│ ┌──────────────┐ │              │
│ │Blob + Table  │◄┼──────────────┘
│ │Storage       │ │
│ │(config,sess) │ │
│ └──────────────┘ │
└──────────────────┘
       ▲
       │
┌──────┴───────────┐       ┌───────────────────────┐       ┌──────────────────┐
│ Azure Functions  │◄──────│ Entra ID              │◄──────│ 👤 User / Admin  │
│ (HTTP) Routing   │       │ Zero Trust + MFA      │ HTTPS │                  │
│ JWT Validation   │       │ Conditional Access    │       │                  │
│ Consumption Tier │       └───────────────────────┘       └──────────────────┘
└──────────────────┘
```

## Components

### Azure Functions (Primary Compute)
- **Purpose**: Handle all webhook requests and dispatch to queue
- **SKU**: Consumption (Y1) - **FREE**: 1M executions/month
- **Runtime**: Node.js 20
- **Triggers**:
  - `HttpTelegram` - Telegram bot webhook
  - `HttpSlack` - Slack events webhook  
  - `HttpDiscord` - Discord interactions
  - `HttpAdmin` - Admin API endpoints
- **Responsibilities**:
  - Validate incoming requests (JWT/signature)
  - Enqueue work items to Storage Queue
  - Return 200 immediately (async processing)

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
- **Purpose**: LLM inference with tool/function calling
- **Model**: GPT-4o-mini (cost-optimized)
- **Auth**: Managed Identity (`DefaultAzureCredential`) — no API key in code
- **Pricing**: Pay-per-token (~$0.15/1M input, ~$0.60/1M output)
- **Features**:
  - **Function/tool calling**: `callModelWithTools()` with up to 5 tool rounds
  - **429 retry with exponential backoff**: Respects `Retry-After` headers (max 3 retries)
  - Response caching (50-80% savings)
  - Token caps (512 max)
  - Content safety filters via `safety.ts`

### MoltBot Agent (Container App)
- **Purpose**: Queue consumer, LLM orchestration, skills execution
- **Image**: `moltbot-agent` built via ACR Tasks (`node:22-alpine` + `python3`)
- **Deployment**: Azure Container App, scale-to-zero (0.25 vCPU, 0.5Gi)
- **Endpoints**: `/webhook/telegram`, `/webhook/slack`, `/healthz`, `/ready`, `/admin/status`
- **Key modules**:
  - `queue-worker.ts` — polls Storage Queue, runs tool-calling loop, always deletes messages in `finally` block
  - `azureOpenAI.ts` — `callModelWithTools()` with 429 retry (exponential backoff, max 3 retries)
  - `skillsRegistry.ts` — 5 skills (bash, text_editor, web-search, calendar-create, email-send)
  - `gateway-client.ts` — OpenClaw WebSocket client with 10s connection timeout
  - `index.ts` — Express server with crypto polyfill for Node.js compatibility

### OpenClaw Gateway (Optional)
- **Purpose**: Enhanced AI agent capabilities via WebSocket
- **Image**: `ghcr.io/openclaw/openclaw:latest`
- **Deployment**: Azure Container App (`molten-dev-openclaw`), internal ingress only
- **Port**: 18789 (WebSocket)
- **Replicas**: min=1, max=1 (must stay running for persistent WebSocket connections)
- **Features**:
  - ClawHub skills registry (bash, text_editor, browser, canvas)
  - Multi-channel routing (WhatsApp, Signal, iMessage, Teams)
  - Session management and conversation persistence
  - Multi-model support (Claude, GPT-4o, etc.)
- **Auth**: Gateway token stored in Key Vault
- **Code**: `src/agent/src/openclaw/gateway-client.ts`

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
4. **Queue dispatch** → Message placed on Azure Storage Queue
5. **Agent picks up** → MoltBot Agent (Container App) polls queue
6. **Content safety** → Pre-filter prompts via `safety.ts`
7. **Route to backend**:
   - **If OpenClaw enabled & connected** → WebSocket to OpenClaw Gateway (10s connection timeout, graceful fallback)
   - **Fallback** → Direct call to Azure OpenAI GPT-4o-mini with tool/function calling
8. **Tool-calling loop** (direct Azure OpenAI mode):
   - Agent calls `callModelWithTools()` with skill definitions (bash, text_editor, web-search, calendar-create, email-send)
   - LLM returns `tool_calls` → Agent executes via `skillsRegistry.executeSkill()`
   - Results fed back to LLM as tool messages
   - Loop repeats up to `MAX_TOOL_ROUNDS = 5` until LLM returns final text
   - **429 rate limit handling**: Exponential backoff with `Retry-After` header respect (max 3 retries)
9. **Queue message cleanup** → Message always deleted in `finally` block (prevents retry stampede)
10. **Cache response** → Store for future hits (5-min TTL)
11. **Send reply** → Back to messaging platform (Telegram, Slack, or Discord)
12. **Log telemetry** → Application Insights

## Skills Architecture

### Skills Flow

```
┌─────────────────┐
│   User Prompt   │
│ "Run df -h cmd" │
└────────┬────────┘
         │
         ▼
┌────────────────────────────────────────┐
│     Azure OpenAI (GPT-4o-mini)         │
│  callModelWithTools() with tool defs   │
│  Returns: tool_calls array             │
│  429 retry: exponential backoff        │
└────────┬───────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────┐
│   queue-worker.ts tool-calling loop    │
│   MAX_TOOL_ROUNDS = 5                  │
│   • Parse tool_calls from response     │
│   • Execute each via skillsRegistry    │
│   • Feed results back as tool messages │
│   • Loop until final text or max rounds│
└────────┬───────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────┐
│   skillsRegistry.executeSkill()        │
│   Routes by skill category:            │
│   • anthropic → Python subprocess      │
│   • azure → TypeScript (Graph/Tavily)  │
│   • custom → User-defined              │
└────────┬───────────────────────────────┘
         │
         ▼
┌────────────────────────────────────────┐
│      User receives response            │
│   (always, even on error: "Sorry...")  │
│   Queue message deleted in finally {}  │
└────────────────────────────────────────┘
```

### Skills Categories

| Category | Skills | Runtime | Cost |
|----------|--------|---------|------|
| **Anthropic** | bash, text_editor | Python subprocess | **$0.00** |
| **Azure** | web-search, calendar, email | TypeScript (Graph API) | **$0-3/mo** |
| **Custom** | User-defined | TypeScript/Python | **$0.00** |

### Skills Security

- **Bash execution**: Dangerous command blocking (`rm -rf /`, fork bombs)
- **File operations**: Restricted to `/tmp` directory
- **Timeouts**: 30s default, configurable per skill
- **Subprocess isolation**: No shell access to container secrets
- **No root access**: Skills run as non-privileged user

### Skills Monitoring

All skill executions logged to **Azure Cosmos DB**:
- `userId` (partition key)
- `skillId`, `skillName`, `skillCategory`
- `parameters`, `success`, `error`
- `duration` (ms), `timestamp`, `cost` ($)

Query example:
```sql
SELECT c.skillId, COUNT(1) as ExecutionCount, AVG(c.duration) as AvgDuration
FROM c
WHERE c.userId = "user123"
GROUP BY c.skillId
```

## Cost Optimization

| Strategy | Implementation | Savings |
|----------|---------------|---------|
| Consumption tier | Pay only when executing | ~$0/mo idle |
| GPT-4o-mini | 10x cheaper than GPT-4 | ~90% on tokens |
| Response cache | In-memory + blob cache | 50-80% fewer API calls |
| Token caps | max_tokens=512 | Bounded per-request |
| Free tiers | All services use free SKUs | ~$0 infrastructure |
| GHCR | GitHub Container Registry | -$5/mo vs ACR |

## Container Apps (Active)

The MoltBot Agent runs as an Azure Container App (`molten-dev-agent`) in the `molten-dev-cae` environment. It polls the Storage Queue and processes messages.

### OpenClaw Gateway (Optional)

When `enable_openclaw = true`, an additional Container App (`molten-dev-openclaw`) is deployed in the same environment with **internal-only ingress**. The agent connects via WebSocket (`wss://`) for enhanced capabilities:

- **Skills**: Full ClawHub registry (bash, text_editor, browser, canvas)
- **Multi-channel**: WhatsApp, Signal, iMessage, Teams (beyond Telegram/Slack/Discord)
- **Models**: Anthropic Claude, OpenAI, and any OpenClaw-supported model
- **Sessions**: Persistent conversation context

The agent falls back to direct Azure OpenAI calls if the Gateway is unavailable.

See `infra/terraform/main.tf` for the OpenClaw Container App resources.
