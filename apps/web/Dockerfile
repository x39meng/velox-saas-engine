FROM oven/bun:1 AS base

FROM base AS builder
WORKDIR /app
COPY . .
RUN bun install
# Build Next.js
cd apps/web && bun run build

FROM base AS runner
WORKDIR /app
ENV NODE_ENV production

# Copy Standalone Output
COPY --from=builder /app/apps/web/.next/standalone ./
COPY --from=builder /app/apps/web/.next/static ./apps/web/.next/static
COPY --from=builder /app/apps/web/public ./apps/web/public

EXPOSE 3000
CMD ["node", "apps/web/server.js"]
