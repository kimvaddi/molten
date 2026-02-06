# Operations Runbook

## Common Operations

### Deploy Infrastructure
```bash
cd infra/terraform
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

### Deploy Functions
```bash
cd src/functions
npm install
npm run build
func azure functionapp publish <function-app-name>
```

### Deploy Agent Container
```bash
cd src/agent

# Build and push via ACR Tasks (from src/agent directory)
az acr build --registry <acr-name> --image moltbot-agent:<version> .

# Update Container App to new image
az containerapp update \
  --name <app-name> \
  --resource-group <rg> \
  --image <acr>.azurecr.io/moltbot-agent:<version>
```

> **Note**: The Dockerfile uses `node:22-alpine` multi-stage build with Python 3 for skills execution. It copies `anthropic_executor.py` into the runtime image.

### Deploy/Update OpenClaw Gateway
```bash
# Check current status
az containerapp show --name molten-dev-openclaw --resource-group molten-dev-rg --query "{status:properties.provisioningState, fqdn:properties.configuration.ingress.fqdn}" -o json

# View OpenClaw logs
az containerapp logs show --name molten-dev-openclaw --resource-group molten-dev-rg --type console --tail 50

# Restart OpenClaw Gateway
az containerapp revision restart --name molten-dev-openclaw --resource-group molten-dev-rg --revision <revision-name>

# Update OpenClaw image
az containerapp update --name molten-dev-openclaw --resource-group molten-dev-rg --image ghcr.io/openclaw/openclaw:latest
```

### Set Telegram Webhook
```bash
curl -X POST "https://api.telegram.org/bot<TOKEN>/setWebhook?url=<FUNCTION_URL>"
```

## Troubleshooting

### Agent Not Processing Messages
1. Check Container App is running:
   ```bash
   az containerapp show --name <app> --resource-group <rg> --query properties.runningStatus
   ```
2. Check queue has messages:
   ```bash
   az storage message peek --queue-name molten-work --account-name <storage>
   ```
3. Check agent logs:
   ```bash
   az containerapp logs show --name <app> --resource-group <rg>
   ```

### OpenClaw Gateway Not Connecting
1. Verify OpenClaw Container App is running:
   ```bash
   az containerapp show --name molten-dev-openclaw --resource-group molten-dev-rg --query "{status:properties.runningState, replicas:properties.template.scale.minReplicas}"
   ```
2. Check Gateway logs for errors:
   ```bash
   az containerapp logs show --name molten-dev-openclaw --resource-group molten-dev-rg --type console --tail 50
   ```
3. Verify agent env vars point to Gateway:
   ```bash
   az containerapp show --name molten-dev-agent --resource-group molten-dev-rg --query "properties.template.containers[0].env[?name=='OPENCLAW_GATEWAY_URL'].value"
   ```
4. Agent falls back to Azure OpenAI automatically — check agent logs for "OpenClaw error, falling back"

### Function Webhook Not Responding
1. Check function is deployed:
   ```bash
   az functionapp function list --name <func-app> --resource-group <rg>
   ```
2. Test health endpoint:
   ```bash
   curl https://<func-app>.azurewebsites.net/api/admin/health
   ```

### High Costs
1. Check token usage in Application Insights
2. Verify cache hit rate in logs
3. Review Container App replica count
4. Check for stuck messages in queue (poison messages)

### 429 Rate Limit Errors
The S0 tier allows only 10 requests/min and 1,000 tokens/min. The agent has built-in retry with exponential backoff.

1. Check agent logs for `429` or `RateLimitReached`:
   ```bash
   az containerapp logs show --name <app> --resource-group <rg> --type console --tail 100 | grep -i "429\|rate"
   ```
2. If persistent, increase Azure OpenAI quota:
   - Go to Azure Portal → Azure OpenAI → Quotas → Request increase
   - Or upgrade from S0 to S1 tier
3. The agent retries up to 3 times with exponential backoff respecting `Retry-After` headers

### Tool-Calling Schema Errors
If you see `Invalid schema for function` errors:
1. Check `skillsRegistry.ts` → `convertParametersToJsonSchema()` ensures `items` property is included for array types
2. Verify skill parameter definitions include proper types
3. Test with: `curl http://localhost:8080/admin/status` to see loaded skills

## Secret Rotation

### Rotate Azure OpenAI Key
1. Generate new key in Azure Portal
2. Update Key Vault secret:
   ```bash
   az keyvault secret set --vault-name <kv> --name azure-openai-api-key --value <new-key>
   ```
3. Restart Container App to pick up new secret

### Rotate Telegram Token
1. Revoke old token via BotFather
2. Get new token from BotFather
3. Update Key Vault secret
4. Update webhook URL

## Scaling

### Increase Container App Capacity
```bash
az containerapp update --name <app> --resource-group <rg> --max-replicas 5
```

### Enable Manual Scaling
```bash
az containerapp update --name <app> --resource-group <rg> --min-replicas 1
```

## Backup & Recovery

### Export Configuration
```bash
az storage blob download-batch --destination ./backup --source molten-configs --account-name <storage>
```

### Terraform State
- State stored in Azure Storage (if remote backend configured)
- Enable versioning on state container
- Regular backups recommended
