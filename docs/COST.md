# Molten - Cost Analysis

## Summary

**Target**: <$5/month  
**Typical Usage**: $2-5/month  
**Region**: West US 3

## Detailed Cost Breakdown

### Azure Services

| Service | SKU | Free Tier | Typical Usage | Est. Cost |
|---------|-----|-----------|---------------|----------|
| Azure Functions | Consumption (Y1) | 1M exec + 400K GB-s | ~10K exec | **$0** |
| Storage Account | Standard LRS | 5GB + 20K ops | ~100MB | **$0** |
| Key Vault | Standard | 10K operations | ~1K ops | **$0** |
| Log Analytics | Free tier | 5GB/month | ~500MB | **$0** |
| Application Insights | Free tier | Included with Log Analytics | ~500MB | **$0** |
| **Azure OpenAI** | Pay-per-token | None | Variable | **$2-5** |

### Azure OpenAI Pricing (GPT-4o-mini)

| Token Type | Price per 1M | Typical Monthly | Est. Cost |
|------------|--------------|-----------------|----------|
| Input | $0.150 | ~500K tokens | $0.08 |
| Output | $0.600 | ~200K tokens | $0.12 |
| Cached Input | $0.075 | ~300K tokens | $0.02 |
| **Total** | | | **~$0.22** |

> **Note**: Heavy usage (1000+ messages/day) could reach $2-5/month.

### Optional Services (Disabled by Default)

| Service | SKU | Monthly Cost | Notes |
|---------|-----|--------------|-------|
| Container Registry | Basic | $5.00 | Use GHCR instead (free) |
| Container Apps | Consumption | $0-10 | Scale-to-zero, pay per use |
| API Management | Consumption | $3.50/million calls | AI gateway features |
| Cosmos DB | Serverless | $0.25/million RU | Use Table Storage instead |

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

### 5. GitHub Container Registry

- **Azure ACR Basic**: $5/month
- **GitHub Container Registry**: FREE for public repos
- **Savings**: $5/month = $60/year

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
