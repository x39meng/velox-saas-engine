FROM oven/bun:1 as base
WORKDIR /app
COPY . .
RUN bun install
WORKDIR /app/apps/api
CMD ["bun", "run", "src/index.ts"]
