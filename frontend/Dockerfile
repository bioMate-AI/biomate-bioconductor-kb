# Frontend Dockerfile (Multi-stage build)
# Use Debian-based node (more stable than Alpine for native modules + esbuild)
FROM node:18-bookworm-slim AS builder

# Install native build tools for better-sqlite3 and other native modules
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files and install ALL deps (including devDeps needed for build)
COPY package*.json ./
RUN npm ci

# Copy application source and build
COPY . .
RUN npm run build

# Production stage — lean runtime image
FROM node:18-bookworm-slim

WORKDIR /app

# Copy built artifacts and prod node_modules from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./


ENV NODE_ENV=production
ENV PORT=3000

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3000/api/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

CMD ["npm", "start"]
