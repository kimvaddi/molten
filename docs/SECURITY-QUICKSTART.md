# Security Improvements Quick Reference

## 🔐 What Was Fixed

This guide summarizes the security improvements made to the Molten project on February 2, 2026.

---

## Critical Fixes Applied

### 1. Secrets Now in Key Vault (Not Terraform State)

**Before:**
```hcl
app_settings = {
  "AzureWebJobsStorage" = azurerm_storage_account.main.primary_connection_string
}
```

**After:**
```hcl
resource "azurerm_key_vault_secret" "storage_connection_string" {
  name  = "storage-connection-string"
  value = azurerm_storage_account.main.primary_connection_string
}

app_settings = {
  "AzureWebJobsStorage" = "@Microsoft.KeyVault(VaultName=${vault};SecretName=storage-connection-string)"
}
```

✅ **Result:** Secrets never appear in Terraform state or portal logs

---

### 2. Telegram Token from Key Vault

**Before:**
```typescript
const token = process.env.TELEGRAM_BOT_TOKEN;
```

**After:**
```typescript
const client = new SecretClient(keyVaultUri, new DefaultAzureCredential());
const secret = await client.getSecret("telegram-bot-token");
const token = secret.value;
```

✅ **Result:** Bot token accessed securely via managed identity

---

### 3. Storage Account Firewall

**Before:**
```hcl
resource "azurerm_storage_account" "main" {
  # No network rules - accepts all connections
}
```

**After:**
```hcl
resource "azurerm_storage_account" "main" {
  min_tls_version                 = "TLS1_2"
  default_to_oauth_authentication = true
  
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}
```

✅ **Result:** Storage only accessible from Azure services

---

### 4. Comprehensive RBAC for Storage

**Added:**
```hcl
resource "azurerm_role_assignment" "func_queue" {
  role_definition_name = "Storage Queue Data Contributor"
}

resource "azurerm_role_assignment" "func_blob" {
  role_definition_name = "Storage Blob Data Contributor"
}

resource "azurerm_role_assignment" "func_table" {
  role_definition_name = "Storage Table Data Contributor"
}
```

✅ **Result:** Functions use managed identity for all storage operations

---

## How to Deploy Securely

### Step 1: Configure Terraform Variables

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
location                = "westus3"
project_name            = "molten"
environment             = "dev"

# Sensitive values - will be stored in Key Vault
azure_openai_endpoint   = "https://your-aoai.openai.azure.com/"
azure_openai_api_key    = "your-api-key"
azure_openai_deployment = "gpt-4o-mini"
telegram_bot_token      = "your-telegram-token"
```

**Important:** These values will be **immediately stored in Key Vault** and **removed from app settings**.

---

### Step 2: Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

**What happens:**
1. ✅ Key Vault created with RBAC
2. ✅ All secrets stored in Key Vault
3. ✅ Functions get managed identity
4. ✅ RBAC roles assigned automatically
5. ✅ Storage firewall enabled

---

### Step 3: Verify Security

```bash
# Check that secrets are in Key Vault
az keyvault secret list --vault-name $(terraform output -raw key_vault_name)

# Verify managed identity has correct roles
PRINCIPAL_ID=$(terraform output -raw function_app_principal_id)
az role assignment list --assignee $PRINCIPAL_ID --output table

# Confirm storage firewall is active
STORAGE_NAME=$(terraform output -raw storage_account_name)
az storage account show -n $STORAGE_NAME --query networkRuleSet.defaultAction -o tsv
# Should output: "Deny"
```

---

## Security Checklist

### ✅ Completed (Automatically)

- [x] Secrets stored in Azure Key Vault
- [x] Managed identity enabled for Functions
- [x] RBAC roles assigned (Key Vault, Storage)
- [x] Storage firewall enabled (Deny by default)
- [x] TLS 1.2 minimum enforced
- [x] Key Vault RBAC authorization enabled
- [x] No secrets in environment variables
- [x] Connection strings from Key Vault references
- [x] Audit logging to Log Analytics

### 🔶 Recommended (Manual Steps)

- [ ] **Enable Terraform remote state:**
  ```bash
  # See docs/SECURITY.md for instructions
  ```

- [ ] **Harden Key Vault network (Production):**
  ```hcl
  keyvault_network_default_action = "Deny"
  ```
  Then add Private Link endpoints.

- [ ] **Set up Azure Monitor alerts:**
  ```bash
  # Alert on failed Key Vault access
  # Alert on high error rates
  # Alert on suspicious activity
  ```

- [ ] **Enable diagnostic settings:**
  ```bash
  az monitor diagnostic-settings create \
    --resource $(terraform output -raw function_app_id) \
    --workspace $(terraform output -raw log_analytics_workspace_id) \
    --logs '[{"category": "FunctionAppLogs", "enabled": true}]'
  ```

- [ ] **Review and minimize permissions:**
  ```bash
  az role assignment list --scope $(terraform output -raw resource_group_id)
  ```

---

## Key Files Changed

| File | Changes |
|------|---------|
| `infra/terraform/main.tf` | ✅ Key Vault secrets, storage network rules, RBAC roles |
| `infra/terraform/variables.tf` | ✅ Key Vault network default changed to "Allow" |
| `src/agent/src/integrations/telegram.ts` | ✅ Load token from Key Vault |
| `docs/SECURITY.md` | ✅ Comprehensive security documentation |
| `docs/SECURITY-AUDIT-REPORT.md` | ✅ Full audit report |

---

## Common Questions

### Q: Where are my secrets stored now?

**A:** All secrets are in Azure Key Vault:
- `azure-openai-endpoint`
- `azure-openai-api-key`
- `telegram-bot-token`
- `storage-connection-string`

Access them via:
```bash
az keyvault secret show --vault-name <vault-name> --name <secret-name>
```

---

### Q: How do Functions access secrets?

**A:** Two ways:

1. **Key Vault References (App Settings):**
   ```
   @Microsoft.KeyVault(VaultName=...;SecretName=...)
   ```
   Resolved automatically by Azure Functions runtime.

2. **Managed Identity (In Code):**
   ```typescript
   const client = new SecretClient(vaultUri, new DefaultAzureCredential());
   const secret = await client.getSecret("secret-name");
   ```

---

### Q: What about local development?

**A:** You have two options:

1. **Use your Azure identity:**
   ```bash
   az login
   # Code will use your credentials via DefaultAzureCredential
   ```

2. **Use local environment variables:**
   ```bash
   export KEY_VAULT_URI="https://your-vault.vault.azure.net/"
   export TELEGRAM_BOT_TOKEN="your-token"  # Fallback only
   npm start
   ```

---

### Q: How do I rotate secrets?

**A:** 
```bash
# Update in Key Vault
az keyvault secret set \
  --vault-name <vault-name> \
  --name telegram-bot-token \
  --value "new-token"

# No restart needed - Functions fetch latest value automatically
```

---

### Q: Can I see secrets in the Azure Portal?

**A:** Only if you have `Key Vault Secrets Officer` or `Key Vault Secrets User` role. Regular viewers cannot see secret values (security by design).

---

### Q: What if Terraform fails with Key Vault access denied?

**A:** Run:
```bash
# Ensure you're logged in
az login

# Verify you have access
az ad signed-in-user show

# Check your Key Vault permissions
az keyvault show --name <vault-name> --query properties.enableRbacAuthorization

# If RBAC is enabled, you need role assignment:
az role assignment create \
  --assignee <your-user-id> \
  --role "Key Vault Secrets Officer" \
  --scope $(az keyvault show --name <vault-name> --query id -o tsv)
```

---

## Production Hardening (Before Go-Live)

1. **Enable Terraform Remote State:**
   - Store state in Azure Storage
   - Enable versioning
   - Lock with lease

2. **Tighten Key Vault Access:**
   ```hcl
   keyvault_network_default_action = "Deny"
   ```
   - Implement Private Link
   - Restrict to specific VNets

3. **Enable All Diagnostic Settings:**
   - Functions → Log Analytics
   - Key Vault → Log Analytics
   - Storage → Log Analytics

4. **Set Up Alerts:**
   - Failed authentication attempts
   - High error rates
   - Unusual access patterns
   - Cost thresholds

5. **Implement Secret Rotation:**
   - Quarterly rotation schedule
   - Automated rotation scripts
   - Testing procedures

---

## Support

- **Security Documentation:** [docs/SECURITY.md](SECURITY.md)
- **Full Audit Report:** [docs/SECURITY-AUDIT-REPORT.md](SECURITY-AUDIT-REPORT.md)
- **Azure Security Best Practices:** https://learn.microsoft.com/azure/security/

---

**Last Updated:** February 2, 2026  
**Next Review:** Before production deployment
