# Frontend Dockerfile — slim app image (~30s rebuild).
# Code execution (`run_code` tool) is delegated to ephemeral biomate-biotools:1
# sandbox containers spawned via the host docker socket — biotools no longer
# live inside this image.
FROM node:18-bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN NODE_OPTIONS=--max-old-space-size=4096 npm run build

# ─── Production stage ─────────────────────────────────────────────────────────
FROM node:18-bookworm-slim

# Docker CLI only — the daemon stays on the host. Socket mount required at run
# time: `-v /var/run/docker.sock:/var/run/docker.sock`.
RUN apt-get update && apt-get install -y --no-install-recommends \
    docker.io ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./
# Migrations are applied by the boot-time runner in server/migrate.ts.
COPY --from=builder /app/migrations ./migrations

ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/api/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

CMD ["npm", "start"]
