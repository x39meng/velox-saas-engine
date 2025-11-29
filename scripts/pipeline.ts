import { $ } from "bun";

console.log("🚀 Starting Pipeline...");

try {
  // 1. Quality
  console.log("🔍 Running Lint...");
  await $`bun run lint`;

  // 2. Build
  console.log("🏗️  Building...");
  await $`bun run build`;

  // 3. Sync Infrastructure Vars
  console.log("🔄 Syncing Infrastructure Variables...");
  await $`bun run infrastructure/scripts/sync-vars.ts`;

  console.log("✅ Pipeline Complete!");
} catch (error) {
  console.error("❌ Pipeline Failed:", error);
  process.exit(1);
}
