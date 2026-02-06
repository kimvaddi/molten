# Security Baseline

## Authentication & Authorization

### Entra ID (Azure AD)
- MFA required for all admin access
- Conditional Access policies enforced
- No service principal secrets - use Managed Identity

### Managed Identity
- All Azure resources use System-Assigned Managed Identity
- No API keys stored in environment variables
- Key Vault accessed via RBAC, not access policies

## Network Security

### HTTPS Only
- TLS 1.2+ enforced on all endpoints
- HSTS headers enabled
- Certificate managed by Azure

### Private Endpoints (Production)
- Storage Account: Private endpoint recommended
- Key Vault: Private endpoint recommended
- Container Apps: Internal ingress option available

## Data Protection

### Key Vault
- Soft-delete enabled (7 days)
- Purge protection: Enable for production
- RBAC authorization (not access policies)

### Storage
- Encryption at rest (Microsoft-managed keys)
- Secure transfer required
- Blob soft delete enabled

## Application Security

### Content Safety
- Input validation on all webhooks
- Prompt injection detection (`safety.ts`) — blocks "ignore previous instructions", "system prompt", "jailbreak"
- Output sanitization (redacts long alphanumeric tokens)
- Token limits (`max_tokens=512`) to prevent abuse
- Input character limit: 4,000 characters

### Safety Patterns Blocked
- `ignore previous instructions`
- `system prompt`
- `jailbreak`
- Sensitive data patterns (passwords, API keys)

### Runtime Security
- **Node.js 22**: Uses `webcrypto` polyfill for compatibility
- **Queue message handling**: Messages always deleted in `finally` block to prevent retry stampede
- **OpenClaw timeout**: 10-second connection timeout prevents infinite hangs; graceful fallback to Azure OpenAI
- **429 retry**: Exponential backoff with max 3 retries; respects `Retry-After` headers
- **Skills sandboxing**: Python subprocess with 30s timeout, restricted to `/tmp`, dangerous commands blocked

## RBAC Assignments

| Principal | Role | Scope |
|-----------|------|-------|
| Functions MI | Key Vault Secrets User | Key Vault |
| Functions MI | Storage Queue Data Contributor | Storage |
| Container App MI | Key Vault Secrets User | Key Vault |
| Container App MI | Storage Blob Data Contributor | Storage |
| Container App MI | Storage Queue Data Contributor | Storage |
| OpenClaw MI | Cognitive Services OpenAI User | Azure OpenAI |
| OpenClaw MI | Key Vault Secrets User | Key Vault |
| OpenClaw MI | Storage Blob Data Contributor | Storage |

## Monitoring & Logging

- Application Insights for telemetry
- Log Analytics for centralized logs
- Azure Monitor alerts for anomalies
- No PII in logs

## Incident Response

1. Rotate compromised secrets in Key Vault
2. Review access logs in Log Analytics
3. Scale down/disable affected components
4. Follow Azure Security Center recommendations
