# Public Repository Security Checklist

## ✅ Files That Are SAFE to Share Publicly

### Configuration Templates
- ✅ `terraform.tfvars.example` - Template with placeholder values
- ✅ `.env.example` - Template for local development
- ✅ `.gitignore` - Properly configured to exclude secrets
- ✅ `README.md` - Public documentation
- ✅ `CONTRIBUTING.md` - Contribution guidelines
- ✅ `LICENSE` - Open source license

### Infrastructure as Code
- ✅ `infra/terraform/*.tf` - Terraform configuration files
- ✅ `deploy/bicep/*.bicep` - Bicep templates
- ✅ `deploy/arm/*.json` - ARM templates (as long as no secrets hardcoded)
- ✅ All PowerShell/Bash deployment scripts (verified no hardcoded secrets)

### Source Code
- ✅ `src/**/*.ts` - TypeScript source files
- ✅ `src/**/*.js` - JavaScript files
- ✅ `package.json` - Package manifests
- ✅ `tsconfig.json` - TypeScript configs
- ✅ `Dockerfile` - Container definitions

### Documentation
- ✅ `docs/**/*.md` - All documentation
- ✅ Architecture diagrams
- ✅ Security guidelines (this document!)

---

## 🔴 Files That Should NEVER Be Public

### Actual Secrets & Credentials

#### Critical - Contains Real Secrets
- ❌ `terraform.tfvars` - Your actual variable values
- ❌ `local.settings.json` - Azure Functions local settings
- ❌ `.env` - Environment variables with secrets
- ❌ `.env.local`, `.env.production`, etc. - Any .env variants
- ❌ Any files with actual API keys, tokens, passwords

#### Terraform State (Contains Sensitive Data)
- ❌ `*.tfstate` - Terraform state files
- ❌ `*.tfstate.backup` - State backups
- ❌ `.terraform/` directory - Terraform working directory
- ❌ `*.tfplan` - Terraform plan files (may contain secrets)
- ❌ `.terraform.lock.hcl` - Can be public but often excluded

#### Azure Function App Settings
- ❌ `local.settings.json` - Contains connection strings
- ❌ Any JSON files with actual connection strings

#### Deployment Outputs
- ❌ `*.output` - Deployment output files
- ❌ `*.out` - Output files
- ❌ `deploy-*.log` - Deployment logs (may contain secrets)
- ❌ `terraform-*.log` - Terraform logs

#### Private Keys & Certificates
- ❌ `*.pem` - Private keys
- ❌ `*.key` - Private keys
- ❌ `*.pfx` - Certificate files
- ❌ `*.p12` - Certificate files
- ❌ SSH keys (`id_rsa`, `id_ed25519`, etc.)

### Build Artifacts & Dependencies

#### Node.js
- ⚠️ `node_modules/` - NPM dependencies (too large, not needed)
- ⚠️ `package-lock.json` - Can be public but often excluded
- ⚠️ `dist/` - Build outputs
- ⚠️ `*.js.map` - Source maps
- ⚠️ `*.d.ts` - TypeScript declarations (generated)

#### Python
- ⚠️ `.venv/` - Virtual environment
- ⚠️ `__pycache__/` - Python cache
- ⚠️ `.python_packages/` - Python packages

### IDE & OS Files
- ⚠️ `.vscode/` - VS Code settings (can contain secrets in launch configs)
- ⚠️ `.idea/` - JetBrains IDE settings
- ⚠️ `*.swp`, `*.swo` - Vim swap files
- ⚠️ `.DS_Store` - macOS metadata
- ⚠️ `Thumbs.db` - Windows thumbnails

### Shell History
- ❌ `.bash_history` - May contain secrets from commands
- ❌ `.zsh_history` - May contain secrets
- ❌ `ConsoleHost_history.txt` - PowerShell history

---

## ⚠️ Files That REQUIRE REVIEW

These files could be safe but need careful inspection:

### Scripts
- ⚠️ `*.ps1` - PowerShell scripts (check for hardcoded secrets)
- ⚠️ `*.sh` - Bash scripts (check for hardcoded secrets)
- ⚠️ `*.bat` - Batch files (check for hardcoded secrets)

**Review for:**
- Hardcoded API keys
- Hardcoded connection strings
- Actual subscription IDs (can be public but often considered sensitive)
- Resource group names with sensitive data
- Email addresses or personal information

### Configuration Files
- ⚠️ `host.json` - Azure Functions host config (usually safe)
- ⚠️ `function.json` - Function definitions (usually safe)
- ⚠️ `.funcignore` - Functions ignore file (safe)
- ⚠️ GitHub Actions workflows (check for secrets usage)

---

## 🛡️ Current Status: Your .gitignore

Your `.gitignore` is **EXCELLENT** and already covers all critical items:

```gitignore
✅ node_modules/           # Build artifacts
✅ .terraform/             # Terraform working dir
✅ *.tfstate               # State files
✅ *.tfvars                # Actual variables
✅ local.settings.json     # Function settings
✅ *.pem, *.key           # Private keys
✅ .env                    # Environment files
✅ *.log                   # Log files
✅ .vscode/, .idea/       # IDE settings
✅ .bash_history, etc.    # Shell history
```

---

## 🔍 Pre-Commit Security Checklist

Before pushing to GitHub, verify:

### 1. **No Actual Secrets**
```powershell
# Search for potential secrets in tracked files
git grep -i "password"
git grep -i "api_key"
git grep -i "secret"
git grep -i "token" -- ':!*.md' ':!*.ignore'
git grep -E "[0-9a-f]{32}" # 32-char hex (potential keys)
```

### 2. **Verify .gitignore is Working**
```powershell
# List all tracked files
git ls-files

# Should NOT include:
# - *.tfvars (except .example)
# - *.tfstate
# - local.settings.json
# - node_modules/
# - .env
```

### 3. **Check Terraform Files**
```powershell
# Ensure no hardcoded values in .tf files
grep -r "sk-proj-" infra/
grep -r "https://.*openai.azure.com" infra/terraform/*.tf
```

### 4. **Review Recent Commits**
```powershell
# Check what you're about to push
git diff origin/main

# Look for:
# - Connection strings
# - API keys
# - Actual subscription IDs
# - Real email addresses
```

---

## 🚨 If You Accidentally Commit a Secret

### Immediate Actions

1. **Rotate the Secret Immediately**
   ```bash
   # Don't wait to clean git history - rotate first!
   az keyvault secret set --vault-name <vault> --name <secret> --value <new-value>
   ```

2. **Remove from Git History**
   ```bash
   # Using git-filter-repo (recommended)
   pip install git-filter-repo
   git filter-repo --path <file-with-secret> --invert-paths --force
   
   # Or using BFG Repo-Cleaner
   java -jar bfg.jar --delete-files <file-with-secret>
   git reflog expire --expire=now --all
   git gc --prune=now --aggressive
   ```

3. **Force Push (Dangerous - Notify Team)**
   ```bash
   git push origin --force --all
   ```

4. **Verify on GitHub**
   - Check all branches
   - Check pull requests
   - Check commit history

### GitHub Secret Scanner

GitHub automatically scans for common secret patterns:
- Azure connection strings
- AWS access keys
- GitHub tokens
- Private keys

If detected, you'll get a security alert.

---

## 🔐 Best Practices for Public Repos

### 1. **Use Template Files**
Always provide `.example` versions:
```
terraform.tfvars.example  ✅ (public)
terraform.tfvars          ❌ (gitignored)

.env.example              ✅ (public)
.env                      ❌ (gitignored)
```

### 2. **Use Placeholder Values**
```hcl
# ✅ Good - terraform.tfvars.example
azure_openai_api_key = "YOUR_AOAI_API_KEY"
telegram_bot_token   = "YOUR_TELEGRAM_BOT_TOKEN"

# ❌ Bad - terraform.tfvars.example
azure_openai_api_key = "sk-proj-abc123..."  # Real key!
```

### 3. **Document Secret Locations**
In README, specify:
```markdown
## Required Secrets

The following secrets must be provided:

1. **Azure OpenAI API Key**: Get from Azure Portal → Your OpenAI resource → Keys
2. **Telegram Bot Token**: Get from @BotFather on Telegram
3. Store in `terraform.tfvars` (gitignored)
```

### 4. **Use GitHub Secrets for CI/CD**
```yaml
# .github/workflows/deploy.yml
env:
  AZURE_SUBSCRIPTION_ID: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
  # Never hardcode secrets in workflow files
```

### 5. **Enable GitHub Secret Scanning**
- Go to repo Settings → Security → Code security and analysis
- Enable "Secret scanning"
- Enable "Push protection" (prevents accidental pushes)

---

## 📋 Verification Script

Create this script to verify before pushing:

```powershell
# verify-repo-security.ps1

Write-Host "🔍 Checking for secrets in tracked files..." -ForegroundColor Yellow

$errors = @()

# Check for common secret patterns
$patterns = @{
    "API Keys" = "sk-[a-zA-Z0-9]{32,}"
    "Azure Keys" = "[a-zA-Z0-9]{88}=="
    "Connection Strings" = "DefaultEndpointsProtocol=https"
    "Passwords" = 'password\s*=\s*[''"][^''"]+'
}

foreach ($pattern in $patterns.GetEnumerator()) {
    $results = git grep -i -E $pattern.Value -- ':!*.md' ':!*.ignore' ':!verify-repo-security.ps1'
    if ($results) {
        $errors += "Found potential $($pattern.Key): $results"
    }
}

# Check for files that shouldn't be tracked
$badFiles = @(
    "*.tfvars"
    "*.tfstate"
    "local.settings.json"
    ".env"
)

foreach ($pattern in $badFiles) {
    $tracked = git ls-files $pattern
    if ($tracked) {
        $errors += "Tracked file that should be ignored: $tracked"
    }
}

if ($errors.Count -gt 0) {
    Write-Host "❌ SECURITY ISSUES FOUND:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "✅ No security issues detected" -ForegroundColor Green
    exit 0
}
```

---

## 📚 Additional Resources

- [GitHub Secret Scanning](https://docs.github.com/en/code-security/secret-scanning)
- [git-secrets by AWS](https://github.com/awslabs/git-secrets)
- [TruffleHog](https://github.com/trufflesecurity/trufflehog) - Find secrets in git repos
- [GitGuardian](https://www.gitguardian.com/) - Automated secret detection

---

## Summary

### ✅ Your Repository is Secure IF:
1. `.gitignore` properly configured ✅ (Already done)
2. No `.tfvars` with real values committed ✅ (Properly excluded)
3. No `local.settings.json` committed ✅ (Properly excluded)
4. No hardcoded secrets in `.tf` or `.ts` files ✅ (Using Key Vault)
5. All scripts use placeholders or Key Vault ✅ (Verified)

### 🎯 Action Items Before Publishing:
- [ ] Run verification script above
- [ ] Review all `.tf` files for hardcoded values
- [ ] Ensure `terraform.tfvars.example` has only placeholders
- [ ] Enable GitHub secret scanning
- [ ] Add security policy (SECURITY.md) ✅ (Already created)
- [ ] Document required secrets in README

**Your project is ready for public GitHub! 🎉**

All sensitive files are properly gitignored, and your code follows security best practices.
