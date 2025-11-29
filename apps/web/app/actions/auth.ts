"use server";
import { HealthCheck } from "@repo/core"; 

export async function checkSystemStatus() {
  // Directly calls the core logic. No API fetch.
  return HealthCheck();
}
