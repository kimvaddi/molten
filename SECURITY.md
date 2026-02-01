# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.x     | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

Instead, please report them via:

1. **GitHub Security Advisories**: Use the "Report a vulnerability" button in the Security tab
2. **Email**: [security@your-domain.com] (replace with your contact)

### What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial Assessment**: Within 1 week
- **Resolution**: Depends on severity

## Security Best Practices

### For Users

1. **Never commit secrets** - Use environment variables or Key Vault
2. **Rotate tokens regularly** - Especially bot tokens and API keys
3. **Use Managed Identity** - Avoid API keys where possible
4. **Enable MFA** - For all Azure accounts
5. **Review RBAC** - Follow least-privilege principle

### Infrastructure Security

| Control | Implementation |
|---------|----------------|
| Secrets Management | Azure Key Vault with Managed Identity |
| Transport Security | HTTPS-only, TLS 1.2+ enforced |
| Authentication | Entra ID + Managed Identity |
| Authorization | Azure RBAC, least-privilege |
| Content Safety | Pre-flight prompt filtering |
| Logging | Application Insights (no secrets logged) |

### Secure Configuration Checklist

- [ ] All secrets stored in Key Vault
- [ ] No secrets in code or config files
- [ ] Managed Identity enabled for all services
- [ ] HTTPS enforced (HTTP disabled)
- [ ] Minimum TLS version set to 1.2
- [ ] RBAC configured with least privilege
- [ ] Application Insights configured (secrets excluded)
- [ ] Network access restricted where possible

## Known Security Considerations

### Azure OpenAI

- Content filtering is enabled by default
- Token caps prevent cost attacks
- Response caching may store sensitive data (configure TTL appropriately)

### Webhook Security

- Telegram: Token validation on every request
- Slack: Signature verification required
- Discord: Interaction signature verification

### Storage Security

- Blob containers are private by default
- Shared access keys can be disabled (use Managed Identity)
- Enable soft delete for data recovery

## Dependency Security

We use Dependabot for automated security updates. Review and merge security PRs promptly.
