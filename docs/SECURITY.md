# Security Best Practices - Molten Azure AI Agent

## Overview

This document outlines the security architecture and best practices implemented in Molten following Microsoft's Azure Well-Architected Framework and Zero Trust principles.

## Security Principles

### 1. **Zero Trust Architecture**
- Never trust, always verify
- Principle of least privilege
- Assume breach mentality
- Defense in depth

### 2. **Identity & Access Management**

#### Managed Identity (Primary Authentication)
✅ **Implemented:**
- System-assigned managed identity for Azure Functions
- Passwordless authentication between Azure services
- RBAC-based access control
- No credentials in code or configuration

```typescript
// ✅ CORRECT: Using managed identity
import { DefaultAzureCredential } from "@azure/identity";
const credential = new DefaultAzureCredential();
const client = new SecretClient(vaultUrl, credential);
```

```typescript
// ❌ WRONG: Never hardcode credentials
const apiKey = "sk-proj-abc123...";
```

#### Azure Key Vault Integration
All secrets stored in Azure Key Vault:
- Azure OpenAI API keys
- Telegram/Slack/Discord bot tokens
- Storage connection strings
- Any third-party API keys

**Key Vault Configuration:**
- RBAC authorization enabled
- Soft delete with 7-day retention
- Purge protection for production
- Network ACLs configured
- Audit logging enabled

### 3. **Secrets Management**

#### Terraform State Security
⚠️ **CRITICAL:** Terraform state files contain sensitive data.

**Best Practices:**
1. **Use Remote State with Encryption:**
```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "yourtfstate"
    container_name       = "tfstate"
    key                  = "molten.tfstate"
    use_azuread_auth    = true  # Use managed identity
  }
}
```

2. **Never commit `.tfstate` files:**
```gitignore
*.tfstate
*.tfstate.backup
*.tfvars          # Except .tfvars.example
```

3. **Encrypt state at rest:**
- Azure Storage encryption enabled by default
- Consider customer-managed keys (CMK) for compliance

#### Key Vault References in App Settings
✅ **Implemented:** App settings use Key Vault references:
```hcl
app_settings = {
  "AzureWebJobsStorage" = "@Microsoft.KeyVault(VaultName=${vault_name};SecretName=storage-connection-string)"
}
```

**Benefits:**
- Secrets never appear in portal or logs
- Automatic rotation support
- Centralized secret management
- Audit trail for access

### 4. **Network Security**

#### Storage Account
✅ **Implemented:**
```hcl
resource "azurerm_storage_account" "main" {
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  
  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}
```

**Security Features:**
- TLS 1.2 minimum
- No public blob access
- Firewall enabled (Azure services allowed)
- Prefer Azure AD authentication over access keys

#### Key Vault
```hcl
resource "azurerm_key_vault" "main" {
  enable_rbac_authorization = true
  purge_protection_enabled  = true  # Production
  soft_delete_retention_days = 7
  
  network_acls {
    default_action = "Allow"  # Or "Deny" with private endpoints
    bypass         = "AzureServices"
  }
}
```

**Recommendations:**
- Use `default_action = "Deny"` in production
- Implement Private Link/Private Endpoints
- Restrict to specific VNets/subnets

### 5. **Data Protection**

#### Encryption at Rest
✅ All Azure services use encryption at rest:
- **Storage**: Microsoft-managed keys (automatic)
- **Key Vault**: FIPS 140-2 Level 2 validated HSMs
- **Application Insights**: Encrypted by default

#### Encryption in Transit
✅ All communication uses TLS 1.2+:
- HTTPS for all endpoints
- TLS for Azure Storage
- Encrypted queue messages

#### Data Retention
```hcl
blob_properties {
  delete_retention_policy {
    days = 7
  }
}

key_vault {
  soft_delete_retention_days = 7
}

log_analytics_workspace {
  retention_in_days = 30
}
```

### 6. **Application Security**

#### Input Validation & Sanitization
✅ **Implemented:**
```typescript
// Block prompt injection attempts
const blockedPatterns = [
  /ignore.*previous.*instructions/i,
  /system.*prompt/i,
  /jailbreak/i,
];

if (blockedPatterns.some((p) => p.test(text))) {
  console.warn(`Blocked suspicious input`);
  return;
}
```

#### Content Safety
✅ Azure OpenAI Content Safety filters:
- Hate speech detection
- Self-harm prevention
- Sexual content filtering
- Violence detection

```typescript
export async function checkSafety(text: string): Promise<SafetyResult> {
  // Azure Content Safety API integration
  // Blocks harmful content before processing
}
```

#### Rate Limiting
🔶 **Recommended:**
- Implement per-user rate limits
- Use Azure API Management for enterprise scenarios
- Monitor usage patterns in Application Insights

### 7. **Monitoring & Auditing**

#### Application Insights
✅ All operations logged:
```typescript
console.log(`Processing message from chat ${chatId}`);
console.warn(`Blocked suspicious input`);
console.error(`Failed to process:`, error);
```

**Queryable in Log Analytics:**
```kql
traces
| where message contains "Blocked"
| where timestamp > ago(24h)
| summarize count() by tostring(customDimensions.chatId)
```

#### Azure Monitor Alerts
🔶 **Recommended:**
```hcl
resource "azurerm_monitor_metric_alert" "high_error_rate" {
  name                = "function-high-error-rate"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_function_app.main.id]
  
  criteria {
    metric_name = "FunctionExecutionUnits"
    aggregation = "Total"
    operator    = "GreaterThan"
    threshold   = 1000
  }
}
```

#### Key Vault Audit Logs
✅ All Key Vault operations logged to Log Analytics:
- Secret access
- Failed authentication attempts
- Permission changes

### 8. **Deployment Security**

#### CI/CD Best Practices
🔶 **Recommended:**
1. **Use Service Principals with RBAC:**
   - Separate SP for each environment
   - Least privilege access
   - Rotate credentials regularly

2. **Secure Pipeline Variables:**
   - Store secrets in Azure DevOps/GitHub Secrets
   - Never log sensitive values
   - Use secret scanning tools

3. **Infrastructure Validation:**
   ```bash
   terraform plan -out=tfplan
   terraform show -json tfplan | tfsec --stdin
   checkov -f main.tf
   ```

#### Secret Rotation
🔶 **Recommended Strategy:**
```
1. Generate new secret
2. Add to Key Vault with version 2
3. Update references
4. Test thoroughly
5. Deprecate old secret
6. Remove after grace period
```

## Security Checklist

### Pre-Production

- [ ] Enable Key Vault purge protection
- [ ] Set Key Vault network default action to "Deny"
- [ ] Implement Private Link for Key Vault
- [ ] Implement Private Link for Storage
- [ ] Configure Azure Firewall or NSG rules
- [ ] Enable Diagnostic Settings on all resources
- [ ] Set up Azure Monitor alerts
- [ ] Configure Azure Sentinel (if required)
- [ ] Review and minimize RBAC assignments
- [ ] Enable MFA for all admin accounts
- [ ] Document incident response procedures

### Production

- [ ] Enable Terraform remote state with encryption
- [ ] Implement secret rotation policy
- [ ] Regular security audits (monthly)
- [ ] Penetration testing (annually)
- [ ] Review access logs (weekly)
- [ ] Update dependencies (weekly)
- [ ] CVE monitoring for all components
- [ ] Backup validation (monthly)
- [ ] Disaster recovery drills (quarterly)

### Compliance

- [ ] GDPR compliance (if handling EU data)
- [ ] HIPAA compliance (if handling health data)
- [ ] PCI-DSS (if handling payment data)
- [ ] SOC 2 Type II audit trail
- [ ] Data residency requirements
- [ ] Right to be forgotten implementation

## Threat Model

### Attack Vectors & Mitigations

| Attack Vector | Risk | Mitigation |
|---------------|------|------------|
| Prompt Injection | HIGH | Input validation, content filtering |
| Secret Exposure | CRITICAL | Key Vault, no hardcoded secrets |
| Data Exfiltration | HIGH | Network restrictions, audit logs |
| DDoS | MEDIUM | Azure Front Door, rate limiting |
| Unauthorized Access | HIGH | Managed Identity, RBAC, MFA |
| Man-in-the-Middle | MEDIUM | TLS 1.2+, certificate pinning |
| Supply Chain | MEDIUM | Dependency scanning, SCA tools |

## Incident Response

### Security Event Response Plan

1. **Detection:**
   - Monitor Azure Monitor alerts
   - Review audit logs daily
   - Anomaly detection in Application Insights

2. **Assessment:**
   - Determine scope and impact
   - Identify affected resources
   - Classify severity (P0-P4)

3. **Containment:**
   - Revoke compromised credentials
   - Isolate affected resources
   - Block malicious IPs

4. **Eradication:**
   - Remove malicious code/access
   - Patch vulnerabilities
   - Rotate all secrets

5. **Recovery:**
   - Restore from backups if needed
   - Verify system integrity
   - Resume normal operations

6. **Post-Incident:**
   - Document timeline and actions
   - Root cause analysis
   - Update security controls

## Contact

For security concerns:
- Report vulnerabilities via GitHub Security Advisories
- Critical issues: [Your security contact email]
- Bug bounty program: [If applicable]

## References

- [Azure Well-Architected Framework - Security](https://learn.microsoft.com/azure/well-architected/security/)
- [Microsoft Security Best Practices](https://learn.microsoft.com/security/benchmark/azure/)
- [Azure Key Vault Best Practices](https://learn.microsoft.com/azure/key-vault/general/best-practices)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Azure Foundations Benchmark](https://www.cisecurity.org/benchmark/azure)

---

**Last Updated:** February 2, 2026  
**Version:** 1.0  
**Owner:** Security Team
