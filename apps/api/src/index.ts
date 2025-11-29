import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { logger } from "@repo/core";
import { API_PORT } from "@repo/config";
import { ipGuard } from "./middleware/ipGuard";
import { createUser, createUserSchema, HealthCheck } from "@repo/core";
import { zValidator } from "@hono/zod-validator";

const app = new Hono();

app.use("*", async (c, next) => {
  const start = Date.now();
  await next();
  const ms = Date.now() - start;
  logger.info({
    method: c.req.method,
    path: c.req.path,
    status: c.res.status,
    duration: ms,
  });
});

app.get("/health", (c) => c.json(HealthCheck()));

// Protected Routes
app.use("/v1/*", ipGuard);

app.post("/v1/users", zValidator("json", createUserSchema), async (c) => {
  const input = c.req.valid("json");
  const user = await createUser(input);
  return c.json(user);
});

logger.info(`Server is running on port ${API_PORT}`);

serve({
  fetch: app.fetch,
  port: API_PORT,
});
