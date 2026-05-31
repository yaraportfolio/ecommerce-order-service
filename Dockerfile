FROM node:18-alpine AS builder
WORKDIR /app

COPY package*.json ./
# On force l'application des overrides en ignorant le lockfile si nécessaire
RUN npm install --omit=dev && npm cache clean --force

COPY src/ ./src/

FROM node:18-alpine
WORKDIR /app

# Mise à jour globale de l'OS pour boucher les trous de sécurité (Busybox, etc.)
RUN apk update && \
    apk upgrade --no-cache && \
    apk add --no-cache libcrypto3 libssl3 busybox ssl_client && \
    rm -rf /var/cache/apk/*

# User non-root
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001

COPY --from=builder --chown=nodejs:nodejs /app /app

USER nodejs
EXPOSE 3003
ENV NODE_ENV=production PORT=3003

CMD ["node", "src/server.js"]