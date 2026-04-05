# Deploy OpenClaw on Azure Container Apps

This guide walks through deploying OpenClaw as an Azure Container App — a serverless container platform that scales to zero and costs nothing at idle.

> **Estimated cost**: $0 at idle (scale-to-zero), ~$2–5/month with moderate usage. See [Cost Breakdown](#cost-breakdown) below.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) >= 2.50
- An Azure subscription ([create free account](https://azure.microsoft.com/free/))
- An Anthropic API key (or Azure OpenAI endpoint)

## Deploy with Azure CLI

```bash
# Variables — customize these
RESOURCE_GROUP="openclaw-rg"
LOCATION="westus3"
CAE_NAME="openclaw-cae"
APP_NAME="openclaw-gateway"
OPENCLAW_MODEL="anthropic/claude-sonnet-4-20250514"

# Login
az login

# Create resource group
az group create --name "$RESOURCE_GROUP" --location "$LOCATION"

# Create Log Analytics workspace (required by Container Apps)
az monitor log-analytics workspace create \
  --workspace-name "openclaw-logs" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --retention-time 30

LOG_ANALYTICS_ID=$(az monitor log-analytics workspace show \
  --workspace-name "openclaw-logs" \
  --resource-group "$RESOURCE_GROUP" \
  --query customerId -o tsv)

LOG_ANALYTICS_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --workspace-name "openclaw-logs" \
  --resource-group "$RESOURCE_GROUP" \
  --query primarySharedKey -o tsv)

# Create Container Apps Environment
az containerapp env create \
  --name "$CAE_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --logs-workspace-id "$LOG_ANALYTICS_ID" \
  --logs-workspace-key "$LOG_ANALYTICS_KEY"

# Deploy OpenClaw Gateway
az containerapp create \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --environment "$CAE_NAME" \
  --image "ghcr.io/openclaw/openclaw:latest" \
  --cpu 0.5 \
  --memory 1Gi \
  --min-replicas 0 \
  --max-replicas 2 \
  --ingress external \
  --target-port 18789 \
  --transport http \
  --env-vars \
    "OPENCLAW_BIND=0.0.0.0" \
    "OPENCLAW_PORT=18789" \
    "OPENCLAW_MODEL=$OPENCLAW_MODEL" \
    "OPENCLAW_THINKING=true"

# Get the Gateway URL
GATEWAY_URL=$(az containerapp show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "properties.configuration.ingress.fqdn" -o tsv)

echo "OpenClaw Gateway: https://$GATEWAY_URL"
```

## Verify Deployment

```bash
# Health check
curl -s "https://$GATEWAY_URL/health" | jq .

# Check container logs
az containerapp logs show \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --tail 20
```

## Configuration

### Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `OPENCLAW_BIND` | Yes | Bind address (`0.0.0.0` for container) |
| `OPENCLAW_PORT` | Yes | Listen port (`18789` default) |
| `OPENCLAW_MODEL` | Yes | Model identifier (e.g., `anthropic/claude-sonnet-4-20250514`) |
| `OPENCLAW_THINKING` | No | Enable extended thinking (`true`/`false`) |
| `OPENCLAW_GATEWAY_TOKEN` | No | Auth token for Gateway API |
| `TELEGRAM_BOT_TOKEN` | No | Telegram integration |
| `AZURE_OPENAI_ENDPOINT` | No | Azure OpenAI as model provider |
| `AZURE_OPENAI_API_KEY` | No | Azure OpenAI API key |
| `AZURE_OPENAI_DEPLOYMENT` | No | Azure OpenAI deployment name |

### Scaling

Container Apps supports scale-to-zero (no HTTP traffic = no cost) and auto-scaling:

```bash
# Update scaling rules
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --min-replicas 0 \
  --max-replicas 5

# Add a custom scaling rule based on concurrent HTTP requests
az containerapp update \
  --name "$APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --scale-rule-name "http-scaling" \
  --scale-rule-type "http" \
  --scale-rule-http-concurrency 10
```

> **Note**: WebSocket connections require `--min-replicas 1` to avoid cold-start disconnections. Set this if using persistent WebSocket connections.

## Cost Breakdown

| Resource | Monthly Cost | Notes |
|----------|-------------|-------|
| Container Apps | $0.00 | 180K vCPU-sec + 360K GiB-sec free/month |
| Log Analytics | $0.00 | 5 GB ingestion free/month |
| Bandwidth | $0.00 | First 100 GB outbound free |
| **Total (infra)** | **$0.00** | At idle or low usage |

Model API costs (Anthropic, OpenAI) are billed separately by the provider.

## Terraform Alternative

If you prefer infrastructure-as-code, see [`infra/terraform/`](https://github.com/kimvaddi/molten/tree/main/infra/terraform) in the Molten project for a complete Terraform module that deploys OpenClaw Gateway alongside an Azure agent:

```hcl
# Enable in terraform.tfvars
enable_openclaw = true
openclaw_model  = "anthropic/claude-sonnet-4-20250514"
```

## Cleanup

Delete all resources when done:

```bash
az group delete --name "$RESOURCE_GROUP" --yes --no-wait
```

Verify deletion:
```bash
az group show --name "$RESOURCE_GROUP" 2>/dev/null || echo "Deleted"
```
