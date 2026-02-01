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
az acr build --registry <acr-name> --image moltbot-agent:latest .
az containerapp update --name <app-name> --resource-group <rg> --image <acr>.azurecr.io/moltbot-agent:latest
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
   az storage message peek --queue-name moltbot-work --account-name <storage>
   ```
3. Check agent logs:
   ```bash
   az containerapp logs show --name <app> --resource-group <rg>
   ```

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
az storage blob download-batch --destination ./backup --source moltbot-configs --account-name <storage>
```

### Terraform State
- State stored in Azure Storage (if remote backend configured)
- Enable versioning on state container
- Regular backups recommended
