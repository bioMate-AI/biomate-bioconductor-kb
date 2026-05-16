# Frontend Dockerfile (app-only, ~30s rebuild)
# Biotools (R, Bioconductor, Python sci, CLI tools) are in biomate-biotools:1 —
# rebuild that image only when biotools deps change (`docker build -f Dockerfile.biotools`).
FROM node:18-bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# ─── Production stage ─────────────────────────────────────────────────────────
# Pre-built biotools base. Build once with:
#   docker build -t biomate-biotools:1 -f Dockerfile.biotools .
FROM biomate-biotools:1

WORKDIR /app

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./

ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/api/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

CMD ["npm", "start"]
