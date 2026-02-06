# Molten - Cost Analysis

## Summary

**Target**: <$10/month
**Typical Usage**: ~$8/month for 1,500 messages
### Azure Services

| Service | Monthly Cost | Notes |
|---------|--------------|-------|
| Azure Functions | $0.00 | 1M executions + 400K GB-s free/month |
| Azure Container Apps | $0.00 | 180K vCPU-sec + 360K GB-s free/month (scale-to-zero) |
| Azure Blob Storage | ~$0.50 | Includes storage + read/write transactions |
| Azure Key Vault | ~$0.03 | $0.03 per 10,000 operations (~200 ops = ~$0.0006, rounded up) |
| Application Insights | $0.00 | 5GB ingestion/month free |
| OpenAI API (GPT-4o-mini) | ~$7.50 | 500K tokens (input/output combined) |
| Bandwidth | $0.00 | First 100GB outbound/month free |
| **TOTAL** | **~$8.03** | **Under $10/month for ~1,500 messages** |

### OpenClaw Gateway (Optional)

When `enable_openclaw = true`, an additional Container App is deployed:

| Resource | Monthly Cost | Notes |
|----------|--------------|-------|
| OpenClaw Container App | ~$0-5 | 0.5 vCPU, 1Gi mem, min_replicas=1 (does NOT scale to zero) |
| ACR (Basic) | ~$5 | Used for agent image builds (`<your-acr-name>`) |
| Gateway token (Key Vault) | ~$0.003 | Additional secret operation |
| **OpenClaw Subtotal** | **~$5-10** | **Increases total to ~$13-18/month** |

> **Note**: The OpenClaw Gateway runs with `min_replicas=1` to maintain persistent WebSocket connections. This means it won't scale to zero and will consume Container Apps compute even when idle. Disable with `enable_openclaw = false` in Terraform to save costs.

### Azure OpenAI Pricing (GPT-4o-mini)

| Token Type | Price per 1M Tokens |
|------------|--------------------|
| Input | $0.15 |
| Output | $0.60 |
| Cached Input | $0.075 |

**Example calculation (1,500 messages/month):**
- ~250K input tokens × $0.15/1M = $0.0375
- ~250K output tokens × $0.60/1M = $0.15
- With overhead and no caching: ~$7.50/month

> **Tip**: Response caching can reduce this by 50-80%.

> **Note on S0 tier**: The free S0 pricing tier allows only 10 requests/minute and 1,000 tokens/minute. The agent includes built-in 429 retry with exponential backoff (`Retry-After` header respect, max 3 retries). Tool-calling requires 2+ API calls per message, so rate limits may cause slight delays. Consider upgrading to S1 for higher throughput.

### Optional Services (Disabled by Default)

| Service | SKU | Monthly Cost | Notes |
|---------|-----|--------------|-------|
| API Management | Consumption | $3.50/million calls | For rate limiting/governance |
| Cosmos DB | Serverless | $0.25/million RU | Use Table Storage instead |

> **Note**: Azure Container Registry (Basic, ~$5/mo) is active for agent image builds. Consider GitHub Container Registry for public repos to save costs.

## Cost Optimization Strategies

### 1. Response Caching (50-80% savings)

```typescript
// Cache responses for 5 minutes
const CACHE_TTL_MS = 5 * 60 * 1000;
const cached = responseCache.get(cacheKey);
if (cached && Date.now() - cached.timestamp < CACHE_TTL_MS) {
  return cached.response; // No OpenAI call!
}
```

### 2. Token Caps (bounded costs)

```typescript
const body = {
  messages,
  max_tokens: 512, // Cap output tokens
  temperature: 0.3, // Lower = more deterministic
};
```

### 3. Model Selection

| Model | Input/1M | Output/1M | Use Case |
|-------|----------|-----------|----------|
| GPT-4o-mini | $0.15 | $0.60 | **Recommended** - best value |
| GPT-4o | $2.50 | $10.00 | Complex reasoning only |
| GPT-4 | $30.00 | $60.00 | Avoid - too expensive |

### 4. Free Tier Maximization

| Service | Free Allowance | Strategy |
|---------|---------------|----------|
| Functions | 1M exec/month | Use only for webhooks |
| Storage | 5GB blob | Compress data, set TTLs |
| Key Vault | 10K ops | Cache secrets in memory |
| Log Analytics | 5GB/month | Sample logs, exclude verbose |

### 5. GitHub Container Registry (Alternative)

- **Azure ACR Basic**: ~$5/month (currently deployed: `<your-acr-name>`)
- **GitHub Container Registry**: FREE for public repos
- **Savings**: $5/month = $60/year if switched to GHCR

## Usage Scenarios

### Low Usage (Personal)
- ~100 messages/day
- ~3K messages/month
- **Cost: $0.50-1.00/month**

### Medium Usage (Small Team)
- ~500 messages/day
- ~15K messages/month
- **Cost: $2-3/month**

### High Usage (Active Community)
- ~2000 messages/day
- ~60K messages/month
- **Cost: $5-10/month**

## Monitoring Costs

### Azure Cost Management

1. Go to **Cost Management + Billing** in Azure Portal
2. Set up **Budget alerts** at $5 and $10
3. Review **Cost analysis** weekly

### Application Insights Queries

```kusto
// Token usage by day
customMetrics
| where name == "openai_tokens"
| summarize TotalTokens = sum(value) by bin(timestamp, 1d)
| order by timestamp desc
```

## Cost Alerts Setup

```bash
# Create budget alert at $5
az consumption budget create \
  --budget-name molten-budget \
  --amount 5 \
  --time-grain Monthly \
  --resource-group molten-dev-rg \
  --notifications '{"Actual_GreaterThan_80_Percent":{"enabled":true,"operator":"GreaterThan","threshold":80,"contactEmails":["your@email.com"]}}'
```
