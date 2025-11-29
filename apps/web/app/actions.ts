"use server";

import { createUser } from "@repo/core";
import { redirect } from "next/navigation";
import { z } from "zod";

export async function signupAction(formData: FormData) {
  const email = formData.get("email") as string;
  const name = formData.get("name") as string;
  
  // In a real app, ID comes from Auth Provider (Clerk/Auth0/Cognito)
  // For MVP, we generate it.
  const id = crypto.randomUUID();

  try {
    await createUser({ id, email, name });
  } catch (e) {
    console.error(e);
    // In real app, return error to UI
    throw new Error("Failed to create user");
  }

  redirect("/dashboard");
}
