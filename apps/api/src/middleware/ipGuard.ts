import { Context, Next } from "hono";
import { db, apiKeys, organizations } from "@repo/database";
import { eq } from "drizzle-orm";
import { logger } from "@repo/core";

export async function ipGuard(c: Context, next: Next) {
  const apiKey = c.req.header("x-api-key");
  if (!apiKey) {
    return c.json({ error: "Missing API Key" }, 401);
  }

  // In a real app, we would hash the key before looking it up
  const [keyRecord] = await db
    .select()
    .from(apiKeys)
    .where(eq(apiKeys.key, apiKey))
    .limit(1);

  if (!keyRecord) {
    return c.json({ error: "Invalid API Key" }, 401);
  }

  const [org] = await db
    .select()
    .from(organizations)
    .where(eq(organizations.id, keyRecord.organizationId))
    .limit(1);

  if (!org) {
    return c.json({ error: "Organization not found" }, 401);
  }

  const clientIp = c.req.header("x-forwarded-for") || "0.0.0.0";
  const allowedIps = org.allowedIps || [];

  if (allowedIps.length === 0 || !allowedIps.includes(clientIp)) {
    logger.warn({ event: "ip_guard.blocked", orgId: org.id, clientIp });
    return c.json({ error: "IP not allowed" }, 403);
  }

  c.set("orgId", org.id);
  await next();
}
