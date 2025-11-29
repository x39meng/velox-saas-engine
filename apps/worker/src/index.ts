import { Worker } from "bullmq";
import { logger } from "@repo/core";
import { csvImportProcessor } from "./processors/csvImport";
import IORedis from "ioredis";

const connection = new IORedis(process.env.REDIS_URL || "redis://localhost:6379");

const worker = new Worker(
  "default-queue",
  async (job) => {
    logger.info({ event: "job.start", jobId: job.id, name: job.name });

    switch (job.name) {
      case "csv-import":
        await csvImportProcessor(job);
        break;
      default:
        logger.warn({ event: "job.unknown", name: job.name });
    }

    logger.info({ event: "job.complete", jobId: job.id });
  },
  { connection }
);

worker.on("failed", (job, err) => {
  logger.error({ event: "job.failed", jobId: job?.id, error: err.message });
});

logger.info("Worker started");
