# ── Stage 1: install dependencies ──────────────────────────────────────────
FROM node:20-alpine AS deps

WORKDIR /app

COPY package*.json ./

# Install production deps only (sharp needs platform-specific binaries)
RUN npm ci --omit=dev

# ── Stage 2: production image ───────────────────────────────────────────────
FROM node:20-alpine AS runner

# Non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy node_modules from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy source
COPY src/ ./src/
COPY package.json ./

# Own files
RUN chown -R appuser:appgroup /app

USER appuser

EXPOSE 3001

CMD ["node", "src/server.js"]
