import { db, users } from "@repo/database";
import { eq } from "drizzle-orm";
import { z } from "zod";
import { logger } from "../logger";

export const createUserSchema = z.object({
  id: z.string(),
  email: z.string().email(),
  name: z.string().optional(),
});

export async function createUser(input: z.infer<typeof createUserSchema>) {
  const { id, email, name } = createUserSchema.parse(input);

  logger.info({ event: "user.create.start", email });

  const [user] = await db
    .insert(users)
    .values({
      id,
      email,
      name,
    })
    .returning();

  logger.info({ event: "user.create.success", userId: user.id });
  return user;
}
