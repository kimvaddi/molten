# PR Plan: Azure Container Apps Deployment Guide for OpenClaw

## Background: What PR #47898 Did (VM Guide)

PR #47898 by **@johnsonshi**, reviewed by **@BradGroux**, was a **docs-only PR** that added an Azure **VM** install guide to the OpenClaw repo. Here's exactly what it touched:

### Files Created/Modified (6 files, +573 lines, -1 line)

| File | Action | Purpose |
|------|--------|---------|
| `docs/docs.json` | Modified | Added nav entries + redirects for `/azure`, `/install/azure`, `/platforms/azure` |
| `docs/install/azure.md` | **Created** | The main Azure VM install guide (169 lines) |
| `docs/platforms/index.md` | Modified | Added "Azure (Linux VM)" link to platforms hub page |
| `docs/vps.md` | Modified | Added "Azure (Linux VM)" link to VPS hub page + updated summary |
| `infra/azure/templates/azuredeploy.json` | **Created** | ARM template (340 lines): VNet, NSG, Bastion, NIC, VM |
| `infra/azure/templates/azuredeploy.parameters.json` | **Created** | ARM parameters file (48 lines) |

### Key Design Decisions in PR #47898

1. **Flat doc file** (`docs/install/azure.md`) — matches existing guides like `gcp.md`, `fly.md`, `hetzner.md`
2. **Infra assets in `infra/azure/templates/`** — kept separate from docs (per reviewer feedback)
3. **No runtime code changes** — pure docs + infra templates
4. **Security posture**: Bastion-only SSH, no public IP, NSG rules, password auth disabled
5. **Cost caveat**: Bastion Standard ~$140/mo + VM ~$55/mo (noted by reviewer — expensive)

### PR Template Structure (Required by OpenClaw)

The PR used OpenClaw's mandatory template with these sections:
- Summary (Problem → Why → What changed → What did NOT change)
- Change Type checkboxes
- Scope checkboxes
- Linked Issue/PR
- User-visible / Behavior Changes
- Security Impact (5 required questions)
- Repro + Verification (Environment, Steps, Expected, Actual — with screenshots)
- Evidence
- Human Verification
- Review Conversations
- Compatibility / Migration
- Failure Recovery
- Risks and Mitigations

---

## Your PR: Azure Container Apps Deployment Guide

### Why This Is Better Than PR #47898's VM Approach

| Aspect | VM (PR #47898) | Container Apps (Your PR) |
|--------|---------------|------------------------|
| **Monthly cost** | ~$195/mo (Bastion + VM) | ~$0-5/mo (scale-to-zero, free tier) |
| **Security** | Bastion SSH, NSG rules | HTTPS ingress only, no SSH needed, Managed Identity |
| **Maintenance** | OS patching, SSH keys | Fully managed, auto-restart |
| **Scaling** | Manual VM resize | Auto-scale 0-N replicas |
| **Setup complexity** | ARM + Bastion + SSH + manual install | Single `az containerapp` command |
| **State** | Local disk (lost on VM delete) | External (Azure Storage) |

### What Your PR Should Touch

#### New Files to Create

1. **`docs/install/azure-container.md`** — Main guide (~150-200 lines)
2. **`infra/azure/container/azuredeploy-container.json`** — ARM template for Container Apps
3. **`infra/azure/container/azuredeploy-container.parameters.json`** — Parameters file

#### Existing Files to Modify

4. **`docs/docs.json`** — Add nav entry + redirects for `/install/azure-container`
5. **`docs/platforms/index.md`** — Add "Azure (Container Apps)" link
6. **`docs/vps.md`** — Add "Azure (Container Apps)" link

---

## Step-by-Step Execution Plan

### Phase 1: Fork and Branch

```bash
# 1. Fork the OpenClaw repo on GitHub
# Go to https://github.com/openclaw/openclaw → Click "Fork"

# 2. Clone your fork
git clone https://github.com/kimvaddi/openclaw.git
cd openclaw

# 3. Create a descriptive branch (match their naming convention)
git checkout -b docs/azure-container-apps-install-guide
```

### Phase 2: Study the Existing Pattern

```bash
# Look at existing install guides to match their format
ls docs/install/
# Expected: gcp.md, fly.md, hetzner.md, azure.md, macos-vm.md, etc.

# Read one to understand the frontmatter and structure
cat docs/install/gcp.md
cat docs/install/azure.md

# Understand docs.json structure
cat docs/docs.json | grep -A5 "azure"
```

### Phase 3: Create the ARM Template

Create `infra/azure/container/azuredeploy-container.json` with these resources:

| Resource | Type | Purpose | Free Tier? |
|----------|------|---------|------------|
| Log Analytics Workspace | Microsoft.OperationalInsights/workspaces | Container App logs | Yes (5GB/mo) |
| Container Apps Environment | Microsoft.App/managedEnvironments | Hosting environment | Yes (free tier) |
| Container App (OpenClaw) | Microsoft.App/containerApps | Run OpenClaw Gateway | Yes (first 2M requests) |
| Storage Account | Microsoft.Storage/storageAccounts | Durable state for OpenClaw | Yes (5GB/mo) |
| User Assigned Managed Identity | Microsoft.ManagedIdentity | Secure auth, no passwords | Yes |

**Security Design:**
- No public SSH — container apps use HTTPS ingress only
- Managed Identity instead of API keys where possible
- Storage account with default-deny network rules + AzureServices bypass
- TLS 1.2+ enforced on storage
- Container runs as non-root (OpenClaw's default image)

**Cost Design (targeting <$5/mo or FREE):**
- Container Apps Consumption plan (scale-to-zero = free when idle)
- Free tier: 180,000 vCPU-seconds + 360,000 GiB-seconds/month
- Storage LRS Standard (cheapest tier, 5GB free)
- Log Analytics (5GB/mo ingestion free)

### Phase 4: Create the Parameters File

Create `infra/azure/container/azuredeploy-container.parameters.json`:

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "value": "westus2" },
    "containerImage": { "value": "ghcr.io/openclaw/openclaw:latest" },
    "cpuCores": { "value": "0.25" },
    "memoryGi": { "value": "0.5" },
    "minReplicas": { "value": 1 },
    "maxReplicas": { "value": 1 }
  }
}
```

### Phase 5: Create the Documentation

Create `docs/install/azure-container.md` following the exact pattern of existing guides.

**Required frontmatter** (match the existing format):
```yaml
---
summary: "Run OpenClaw Gateway on Azure Container Apps with scale-to-zero and free-tier pricing"
read_when:
  - You want OpenClaw running on Azure with minimal cost (free tier eligible)
  - You want a containerized, auto-scaling OpenClaw Gateway without managing VMs
  - You want managed HTTPS ingress without configuring SSL certificates
  - You want repeatable deployments with Azure Resource Manager templates
title: "Azure Container Apps"
---
```

**Guide structure** (match existing patterns):

1. **What you'll do** — Deploy Container Apps Environment + OpenClaw container
2. **Before you start** — Azure subscription, Azure CLI, Docker (optional for custom images)
3. **Sign in to Azure CLI**
4. **Register required resource providers** (Microsoft.App, Microsoft.OperationalInsights, Microsoft.Storage)
5. **Set deployment variables**
6. **Create the resource group**
7. **Deploy resources** (ARM template or `az containerapp` commands)
8. **Verify the Gateway** — `az containerapp show` + curl FQDN
9. **Install OpenClaw / Configure** — Run onboarding via container exec or env vars
10. **Cost considerations** — Free tier limits, how to deallocate
11. **Cleanup** — `az group delete`
12. **Next steps** — Channels, Nodes, Gateway configuration

### Phase 6: Update Navigation Files

#### `docs/docs.json`

Add redirects (same pattern as azure.md):
```json
{
  "source": "/azure-container",
  "destination": "/install/azure-container"
},
{
  "source": "/platforms/azure-container",
  "destination": "/install/azure-container"
}
```

Add to nav pages array:
```json
"install/azure-container",
```

#### `docs/platforms/index.md`

Add after the Azure (Linux VM) entry:
```markdown
- Azure (Container Apps): [Azure Container Apps](/install/azure-container)
```

#### `docs/vps.md`

Update summary and add link:
```markdown
- **Azure (Container Apps)**: [Azure Container Apps](/install/azure-container)
```

### Phase 7: Local Validation

```bash
# 1. Build the OpenClaw docs site locally
npm install  # or whatever their build system is
npm run build

# 2. Verify no broken links
# Open locally and check all new links resolve

# 3. Validate ARM template syntax
az deployment group validate \
  -g test-rg \
  --template-file infra/azure/container/azuredeploy-container.json \
  --parameters infra/azure/container/azuredeploy-container.parameters.json

# 4. Actually deploy in a test Azure subscription
az group create -n rg-openclaw-container-test -l westus2
az deployment group create \
  -g rg-openclaw-container-test \
  --template-file infra/azure/container/azuredeploy-container.json \
  --parameters infra/azure/container/azuredeploy-container.parameters.json

# 5. Verify OpenClaw is running
az containerapp show -n ca-openclaw -g rg-openclaw-container-test --query properties.configuration.ingress.fqdn -o tsv
# curl the FQDN to verify

# 6. Take screenshots of:
#    - Azure portal showing deployed resources
#    - Container App logs showing OpenClaw running
#    - OpenClaw status/health endpoint response
#    - Telegram bot interaction (if configured)

# 7. Clean up test resources
az group delete -n rg-openclaw-container-test --yes --no-wait
```

### Phase 8: Commit and Push

```bash
# Stage all files
git add docs/install/azure-container.md
git add infra/azure/container/azuredeploy-container.json
git add infra/azure/container/azuredeploy-container.parameters.json
git add docs/docs.json
git add docs/platforms/index.md
git add docs/vps.md

# Commit with their conventional format
git commit -m "docs: add Azure Container Apps deployment guide with ARM templates"

# Push to your fork
git push origin docs/azure-container-apps-install-guide
```

### Phase 9: Submit the PR

Go to `https://github.com/openclaw/openclaw/compare/main...kimvaddi:docs/azure-container-apps-install-guide`

Fill out the PR template **exactly** as PR #47898 did:

---

**Title:** `docs: add Azure Container Apps deployment guide with in-repo ARM templates`

**Summary:**
- **Problem**: OpenClaw docs have a VM-based Azure guide but no container-based option. The VM guide (PR #47898) costs ~$195/month. Azure users need a free-tier-friendly container path.
- **Why it matters**: Azure Container Apps offer scale-to-zero, managed HTTPS, and free-tier eligibility — making OpenClaw accessible to users who can't afford $195/month.
- **What changed**: Added a new Azure Container Apps install guide (`docs/install/azure-container.md`), ARM templates (`infra/azure/container/`), and nav/redirect updates.
- **What did NOT change**: No Gateway/runtime code, auth logic, provider behavior, or installer execution behavior changed.

**Change Type:** ☑ Docs, ☑ Chore/infra

**Scope:** ☑ CI/CD / infra, ☑ UI / DX

**Security Impact:**
- New permissions/capabilities? `No`
- Secrets/tokens handling changed? `No`
- New/changed network calls? `No`
- Command/tool execution surface changed? `No`
- Data access scope changed? `No`

**Repro + Verification:**
Include complete steps with screenshots showing:
1. ARM template deployment succeeding
2. Container App running in Azure Portal
3. OpenClaw health endpoint responding
4. (Bonus) Telegram bot interaction if configured

**Failure Recovery:**
- How to revert: Revert this PR/commit
- Files to restore: `docs/docs.json`, `docs/vps.md`, `docs/platforms/index.md`, remove `docs/install/azure-container.md` and `infra/azure/container/`

---

## Phase 10: Address Review Feedback

Based on the PR #47898 review patterns, expect these reviewer concerns:

1. **Cost callout** — Add explicit monthly cost notes (BradGroux always asks for this)
2. **Cleanup section** — Include `az group delete` command prominently
3. **Directory structure** — Match flat file pattern in `docs/install/`
4. **Security patterns** — Explain why container approach is MORE secure than VM (no SSH surface)
5. **Greptile bot** — Will auto-review; address any feedback it raises

---

## Key Lessons from PR #47898

1. **Be thorough with screenshots** — They expect end-to-end proof of deployment working
2. **BradGroux is the Azure reviewer** — He's the maintainer for Microsoft/Azure PRs
3. **Follow existing patterns** — Flat file in `docs/install/`, infra in `infra/azure/`
4. **Cost transparency matters** — The biggest critique of #47898 was the cost (~$195/mo)
5. **Security first** — NSG rules, no public IPs, Managed Identity, TLS enforcement
6. **Address Greptile bot feedback** — Resolve all bot conversations yourself
7. **PR #49126** tracks all Microsoft issues — Your PR may get linked there
8. **PR #50700** already replaced ARM with pure CLI — Consider whether to use ARM or CLI approach

---

## Leveraging Your Molten Codebase

Your existing Terraform in `infra/terraform/main.tf` already has a production-grade Container Apps setup with:
- Container Apps Environment + Agent Container App
- Optional OpenClaw Gateway Container App
- Managed Identity + RBAC roles
- Storage Queue + Table integration
- Key Vault integration
- Scale-to-zero configuration

**You can directly adapt this knowledge** for the OpenClaw PR ARM template. The key difference:
- Molten deploys OpenClaw as a **sidecar** to the Agent
- The OpenClaw PR should deploy OpenClaw as a **standalone** Container App
- Focus on the simplest possible deployment (single container, minimal dependencies)
