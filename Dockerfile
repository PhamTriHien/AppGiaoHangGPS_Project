FROM node:22-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app/gps_delivery_app/backend/otp-relay

COPY gps_delivery_app/backend/otp-relay/package.json gps_delivery_app/backend/otp-relay/package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY gps_delivery_app/database/migrations /app/gps_delivery_app/database/migrations
COPY gps_delivery_app/backend/otp-relay /app/gps_delivery_app/backend/otp-relay

RUN chown -R node:node /app

USER node

ENV NODE_ENV=production \
    BIND_HOST=0.0.0.0 \
    PORT=8787 \
    TRUST_PROXY=1 \
    ADMIN_PORTAL_ONLY=true

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||8787)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.mjs"]
