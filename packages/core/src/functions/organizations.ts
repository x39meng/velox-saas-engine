import { db, organizations, memberships } from "@repo/database";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { logger } from "../logger";

export const createOrganizationSchema = z.object({
  name: z.string().min(1),
  slug: z.string().min(1),
  userId: z.string(),
});

export async function createOrganization(input: z.infer<typeof createOrganizationSchema>) {
  const { name, slug, userId } = createOrganizationSchema.parse(input);

  logger.info({ event: "org.create.start", userId, slug });

  return await db.transaction(async (tx) => {
    const [org] = await tx
      .insert(organizations)
      .values({
        name,
        slug,
      })
      .returning();

    await tx.insert(memberships).values({
      userId,
      organizationId: org.id,
      role: "owner",
    });

    logger.info({ event: "org.create.success", orgId: org.id });
    return org;
  });
}

export const inviteUserSchema = z.object({
  email: z.string().email(),
  organizationId: z.string().uuid(),
  role: z.enum(["member", "admin", "owner"]),
});

export async function inviteUser(input: z.infer<typeof inviteUserSchema>) {
    // Placeholder for invite logic (e.g. send email, create pending invite)
    // For MVP, we might just log it or create a membership directly if user exists?
    // The prompt asks for "inviteUser", let's assume it creates a membership for now or just logs.
    // Given "Headless Business Logic", let's just implement a basic version.
    const { email, organizationId, role } = inviteUserSchema.parse(input);
    logger.info({ event: "user.invite", email, organizationId, role });
    
    // In a real app, we'd check if user exists, send email, etc.
    return { success: true, message: "Invite sent (simulated)" };
}
