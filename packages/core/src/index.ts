export * from "./logger";
export * from "./functions/users";
export * from "./functions/organizations";

export const HealthCheck = () => ({ status: "ok", timestamp: new Date() });

export const validateClientIP = (clientIp: string, allowedIps: string[]) => {
  return allowedIps.includes(clientIp);
};
