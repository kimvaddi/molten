# Pin to SHA256 digest for reproducible builds
FROM node:22-alpine@sha256:9bef0ef1e268f60627da9ba7d7605e8831d5b56ad07487d24d1aa386336d1944 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --ignore-scripts
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-alpine@sha256:9bef0ef1e268f60627da9ba7d7605e8831d5b56ad07487d24d1aa386336d1944 AS runtime

# OCI image labels
LABEL org.opencontainers.image.source="https://github.com/kimvaddi/molten"
LABEL org.opencontainers.image.description="Molten AI Agent - Azure free-tier chatbot"
LABEL org.opencontainers.image.licenses="MIT"

WORKDIR /app

# Install Python for skills executor (bash, text_editor)
RUN apk add --no-cache python3

# Security: non-root user
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001

COPY --from=builder --chown=nodejs:nodejs /app/dist ./dist
COPY --from=builder --chown=nodejs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nodejs:nodejs /app/package.json ./

# Copy Python skills executor
COPY --chown=nodejs:nodejs src/skills/anthropic_executor.py ./dist/skills/anthropic_executor.py

USER nodejs
EXPOSE 8080
ENV NODE_ENV=production
ENV PORT=8080

# start-period=30s allows for Key Vault credential exchange + OpenClaw init
HEALTHCHECK --interval=2m --timeout=5s --start-period=30s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/healthz || exit 1

CMD ["node", "dist/index.js"]
