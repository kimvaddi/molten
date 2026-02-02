# Repository Security Verification Script
# Run this before pushing to GitHub

Write-Host "`n🔐 Molten Repository Security Check`n" -ForegroundColor Cyan

$errors = @()
$warnings = @()

# ============================================================================
# 1. Check for sensitive files in git tracking
# ============================================================================
Write-Host "📂 Checking tracked files..." -ForegroundColor Yellow

$sensitivePatterns = @{
    "Terraform Variables" = "\.tfvars$"
    "Terraform State" = "\.tfstate"
    "Environment Files" = "^\.env$"
    "Local Settings" = "local\.settings\.json"
    "Private Keys" = "\.(pem|key|pfx)$"
    "Shell History" = "(bash_history|zsh_history|ConsoleHost_history)"
    "Node Modules" = "node_modules/"
    "Virtual Env" = "\.venv/"
}

foreach ($check in $sensitivePatterns.GetEnumerator()) {
    $found = git ls-files | Select-String -Pattern $check.Value
    if ($found) {
        # Exception: .tfvars.example is OK
        if ($check.Key -eq "Terraform Variables" -and $found -match "\.example$") {
            Write-Host "  ✅ $($check.Key): Only .example files found" -ForegroundColor Green
        } else {
            $errors += "$($check.Key) tracked in git: $found"
        }
    } else {
        Write-Host "  ✅ $($check.Key): None tracked" -ForegroundColor Green
    }
}

# ============================================================================
# 2. Scan for hardcoded secrets in code
# ============================================================================
Write-Host "`n🔍 Scanning for hardcoded secrets..." -ForegroundColor Yellow

$secretPatterns = @{
    "Azure OpenAI Keys" = "sk-[a-zA-Z0-9-]{32,}"
    "Base64 Keys (88 chars)" = "[a-zA-Z0-9+/]{88}=="
    "Connection Strings" = "DefaultEndpointsProtocol=https;AccountName="
    "Bot Tokens" = "[0-9]{8,10}:[A-Za-z0-9_-]{35}"
    "Generic Secrets" = 'secret["'']?\s*[:=]\s*["''][^"'']{20,}'
}

$filesToCheck = git ls-files | Where-Object { 
    $_ -match '\.(ts|js|tf|ps1|sh|yml|yaml)$' -and 
    $_ -notmatch '(node_modules|\.example|\.md)'
}

foreach ($pattern in $secretPatterns.GetEnumerator()) {
    $results = @()
    foreach ($file in $filesToCheck) {
        $matches = Select-String -Path $file -Pattern $pattern.Value -ErrorAction SilentlyContinue
        if ($matches) {
            $results += $matches
        }
    }
    
    if ($results) {
        # Check if it's just a placeholder or example
        $realSecrets = $results | Where-Object { 
            $_.Line -notmatch "(YOUR_|EXAMPLE_|placeholder|<your-|xxx|000)" 
        }
        
        if ($realSecrets) {
            $errors += "$($pattern.Key) found in: $($realSecrets.Path -join ', ')"
        } else {
            Write-Host "  ✅ $($pattern.Key): Only placeholders found" -ForegroundColor Green
        }
    } else {
        Write-Host "  ✅ $($pattern.Key): None found" -ForegroundColor Green
    }
}

# ============================================================================
# 3. Verify .gitignore is present and comprehensive
# ============================================================================
Write-Host "`n📋 Checking .gitignore..." -ForegroundColor Yellow

if (Test-Path ".gitignore") {
    $gitignore = Get-Content ".gitignore" -Raw
    
    $requiredPatterns = @(
        "*.tfvars",
        "*.tfstate",
        "local.settings.json",
        ".env",
        "*.pem",
        "*.key",
        "node_modules",
        ".venv"
    )
    
    $missing = @()
    foreach ($pattern in $requiredPatterns) {
        if ($gitignore -notmatch [regex]::Escape($pattern)) {
            $missing += $pattern
        }
    }
    
    if ($missing) {
        $warnings += ".gitignore missing patterns: $($missing -join ', ')"
    } else {
        Write-Host "  ✅ .gitignore is comprehensive" -ForegroundColor Green
    }
} else {
    $errors += ".gitignore file not found!"
}

# ============================================================================
# 4. Check for example files
# ============================================================================
Write-Host "`n📝 Checking example/template files..." -ForegroundColor Yellow

$requiredExamples = @(
    "infra/terraform/terraform.tfvars.example"
)

foreach ($example in $requiredExamples) {
    if (Test-Path $example) {
        # Verify it only has placeholders
        $content = Get-Content $example -Raw
        if ($content -match "(sk-proj-[a-zA-Z0-9]{32}|[0-9]{9,}:[A-Za-z0-9_-]{35}|[a-zA-Z0-9+/]{88}==)") {
            $warnings += "$example may contain real secrets instead of placeholders"
        } else {
            Write-Host "  ✅ $example exists with placeholders" -ForegroundColor Green
        }
    } else {
        $warnings += "$example not found - users won't know how to configure"
    }
}

# ============================================================================
# 5. Check documentation
# ============================================================================
Write-Host "`n📚 Checking security documentation..." -ForegroundColor Yellow

$requiredDocs = @(
    "docs/SECURITY.md",
    "docs/SECURITY-AUDIT-REPORT.md",
    "docs/PUBLIC-REPO-SECURITY-CHECKLIST.md"
)

foreach ($doc in $requiredDocs) {
    if (Test-Path $doc) {
        Write-Host "  ✅ $doc exists" -ForegroundColor Green
    } else {
        $warnings += "$doc not found"
    }
}

# ============================================================================
# 6. Verify Key Vault usage in code
# ============================================================================
Write-Host "`n🔑 Verifying Key Vault integration..." -ForegroundColor Yellow

$tsFiles = Get-ChildItem -Recurse -Filter "*.ts" -Exclude "node_modules"
$keyVaultUsage = Select-String -Path $tsFiles.FullName -Pattern "SecretClient|getSecret|KeyVaultSecret" -ErrorAction SilentlyContinue

if ($keyVaultUsage) {
    Write-Host "  ✅ Key Vault integration found in code" -ForegroundColor Green
} else {
    $warnings += "No Key Vault usage detected in TypeScript code"
}

# Check for direct env var usage of secrets
$directSecrets = Select-String -Path $tsFiles.FullName -Pattern 'process\.env\.(API_KEY|SECRET|PASSWORD|TOKEN)' -ErrorAction SilentlyContinue
if ($directSecrets) {
    $warnings += "Direct env var access to secrets found - should use Key Vault: $($directSecrets.Path -join ', ')"
}

# ============================================================================
# 7. Check if git history is clean
# ============================================================================
Write-Host "`n📜 Checking git history for leaked secrets..." -ForegroundColor Yellow

# This is a basic check - for thorough scanning use tools like TruffleHog
$logCheck = git log --all --pretty=format:"%H" | Select-Object -First 100
$historyIssues = @()

foreach ($commit in $logCheck) {
    $diff = git show $commit --pretty=format:'' 2>$null
    
    # Check for actual secrets, not template references
    # Exclude ARM/Bicep template syntax: ${var}, [concat(...)]
    $actualSecrets = $diff | Select-String -Pattern "sk-proj-[a-zA-Z0-9-]{32}" -ErrorAction SilentlyContinue
    
    # Check for connection strings that aren't template references
    $connectionStrings = $diff | Select-String -Pattern "DefaultEndpointsProtocol=https;AccountName=[a-z0-9]{3,24};AccountKey=[A-Za-z0-9+/=]{88}" -ErrorAction SilentlyContinue
    
    if ($actualSecrets -or $connectionStrings) {
        # Verify it's not just a template
        $isTemplate = $diff -match "(\[concat\(|listKeys\(|\$\{storageAccount|variables\()"
        if (-not $isTemplate) {
            $historyIssues += $commit
        }
    }
}

if ($historyIssues) {
    $errors += "Potential secrets found in git history at commits: $($historyIssues -join ', ')"
    Write-Host "  ⚠️  Run 'git log -p | Select-String pattern' to investigate" -ForegroundColor Red
} else {
    Write-Host "  ✅ Recent git history appears clean (templates OK)" -ForegroundColor Green
}

# ============================================================================
# RESULTS
# ============================================================================
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "SECURITY VERIFICATION RESULTS" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

if ($errors.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "`n✅ ALL CHECKS PASSED! Repository is safe for public GitHub." -ForegroundColor Green
    Write-Host "`nYour repository follows security best practices:" -ForegroundColor Green
    Write-Host "  ✓ No sensitive files tracked" -ForegroundColor Green
    Write-Host "  ✓ No hardcoded secrets in code" -ForegroundColor Green
    Write-Host "  ✓ .gitignore properly configured" -ForegroundColor Green
    Write-Host "  ✓ Example files present" -ForegroundColor Green
    Write-Host "  ✓ Security documentation complete" -ForegroundColor Green
    Write-Host "  ✓ Key Vault integration implemented" -ForegroundColor Green
    Write-Host "`n🚀 Ready to push to https://github.com/kimvaddi/molten/`n" -ForegroundColor Green
    exit 0
}

if ($errors.Count -gt 0) {
    Write-Host "`n❌ CRITICAL ISSUES FOUND:" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
    Write-Host "`n🛑 DO NOT PUSH TO GITHUB until these are resolved!`n" -ForegroundColor Red
}

if ($warnings.Count -gt 0) {
    Write-Host "`n⚠️  WARNINGS:" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
    Write-Host "`nThese should be addressed but won't block deployment.`n" -ForegroundColor Yellow
}

if ($errors.Count -gt 0) {
    exit 1
} else {
    exit 0
}
