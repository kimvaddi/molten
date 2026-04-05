# Project Guidelines

Molten (MoltBot) — self-hosted Azure AI agent for Telegram, Slack, Discord, WhatsApp. Targets <$10/month on Azure free tiers. Optional [OpenClaw](https://github.com/openclaw/openclaw) integration for enhanced skills.

## Architecture

Platform webhook → **Functions** (HMAC validate + enqueue) → Storage Queue (base64) → **Agent** queue-worker (poll) → [OpenClaw | Azure OpenAI] → Skills (up to 5 tool rounds) → Cache → Integration reply → Table Storage (history)

| Layer | Path | Role |
|-------|------|------|
| Functions | `src/functions/` | Webhook receivers, signature validation, queue dispatch |
| Agent | `src/agent/` | Express server, queue worker, LLM calls, skills |
| Shared | `src/shared/` | Types (`types.ts`), config (`config.ts`), logger |
| Infra | `infra/terraform/` | All Azure resources (Terraform recommended) |

See [docs/architecture.md](docs/architecture.md) for detailed diagrams and component descriptions.

## Build and Test

```bash
# Agent
cd src/agent && npm install && npm run build && npm test

# Functions (requires Azure Functions Core Tools >= 4.x)
cd src/functions && npm install && npm run build && npm test

# Infrastructure
cd infra/terraform && terraform init && terraform validate

# Local dev (optional Azurite emulator)
docker compose -f docker-compose.dev.yml up
```

- Jest with ts-jest preset; tests in `src/agent/src/__tests__/`
- **>80% coverage** for new code; no live Azure calls — mock all SDK clients
- Use `jest.useFakeTimers()` for TTL/expiry testing
- Run `terraform validate` for any infrastructure changes

See [CONTRIBUTING.md](CONTRIBUTING.md) for full dev setup, PR process, and commit conventions.

## Code Style

- TypeScript strict mode, ES2020, CommonJS modules
- Async/await; early return for validation
- Interface-first: define in `src/shared/types.ts` before implementing
- Structured JSON logging via `src/agent/src/utils/logger.ts` — level controlled by `LOG_LEVEL`
- Module-level caching for Azure SDK clients (initialize once at file scope)
- Commits: `type(scope): description` — see [CONTRIBUTING.md](CONTRIBUTING.md)

## Conventions

- **Secrets**: Key Vault + Managed Identity only, never in code. Use `@Microsoft.KeyVault(...)` in app settings
- **Auth**: `DefaultAzureCredential` for all Azure service-to-service calls
- **Webhooks**: Every platform validates HMAC before processing — see `src/agent/src/utils/auth.ts`
- **Queue encoding**: Messages are base64-encoded; decode before parsing
- **LLM costs**: max_tokens=512; response cache with 5-min TTL in `src/agent/src/utils/cache.ts`
- **Input limit**: 4000 chars enforced at Functions and queue-worker layers
- **Output sanitization**: Redacts 32+ char alphanumeric tokens as `[REDACTED]`
- **Skills**: Python subprocess with JSON I/O, sandboxed to `/tmp`, 30s timeout, dangerous commands blocked
- **Dockerfile**: Base image pinned to SHA256, `npm ci`, non-root user, health check

## Extending the Project

**New platform**: Function in `src/functions/Http<Platform>/` (validate + enqueue) → handler in `src/agent/src/integrations/<platform>.ts` → add channel to `WorkItem` in `types.ts` → dispatch in `queue-worker.ts` → Key Vault + Terraform vars

**New skill**: Register in `src/agent/src/skills/skillsRegistry.ts` with name + JSON schema → implement as TypeScript function or Python subprocess

## Gotchas

- **S0 rate limit**: 10 req/min — tool loops (5 rounds max) can exhaust this quickly
- **24h conversation TTL**: Table Storage messages purge after 24 hours
- **OpenClaw costs**: `min_replicas=1` means $5–10/month even when idle
- **Purge protection off in dev**: `main.tf` sets `purge_protection_enabled = false` — set `true` for production

## Further Reading

| Topic | Doc |
|-------|-----|
| Deployment & setup | [docs/GETTING-STARTED.md](docs/GETTING-STARTED.md) |
| Operations | [docs/runbook.md](docs/runbook.md) |
| Cost breakdown | [docs/COST.md](docs/COST.md) |
| Security controls | [docs/SECURITY.md](docs/SECURITY.md), [docs/SECURITY-QUICKSTART.md](docs/SECURITY-QUICKSTART.md) |
| OpenClaw on Container Apps | [docs/azure-container-apps.md](docs/azure-container-apps.md) |
| Skills integration | [docs/SKILLS-INTEGRATION.md](docs/SKILLS-INTEGRATION.md) |
| Gap analysis | [docs/GAP-ANALYSIS.md](docs/GAP-ANALYSIS.md) |
