import { Job } from "bullmq";
import { logger } from "@repo/core";
import { db, users } from "@repo/database";

// Mock S3 download
async function downloadFromS3(key: string): Promise<string> {
  return `email,name
test1@example.com,Test User 1
test2@example.com,Test User 2`;
}

export async function csvImportProcessor(job: Job) {
  const { s3Key, organizationId } = job.data;
  
  logger.info({ event: "csv_import.start", s3Key });

  const csvContent = await downloadFromS3(s3Key);
  
  // Parse CSV (Simplified for MVP)
  const lines = csvContent.split("\n").slice(1); // Skip header
  const usersToInsert = lines.map(line => {
    const [email, name] = line.split(",");
    return {
      id: crypto.randomUUID(),
      email: email.trim(),
      name: name?.trim(),
    };
  });

  if (usersToInsert.length > 0) {
    await db.insert(users).values(usersToInsert);
  }

  logger.info({ event: "csv_import.success", count: usersToInsert.length });
}
