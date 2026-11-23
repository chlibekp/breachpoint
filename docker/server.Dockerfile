# Game server / gateway image. TypeScript runs via tsx so there is no separate build step yet;
# milestone 4 switches to a compiled bundle for match workers.
FROM node:22-bookworm-slim
WORKDIR /app
COPY package.json package-lock.json ./
COPY shared/package.json shared/package.json
COPY server/package.json server/package.json
RUN npm ci --omit=dev --ignore-scripts && npm install --no-save tsx@4
COPY shared shared
COPY server server
ENV NODE_ENV=production PORT=7350
EXPOSE 7350
USER node
CMD ["npx", "tsx", "server/src/main.ts"]
