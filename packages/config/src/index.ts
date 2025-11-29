export const API_PORT = 3001;
export const WEB_PORT = 3000;

export const SERVICE_NAMES = {
  API: "velox-api",
  WEB: "velox-web",
  WORKER: "velox-worker",
};

export const APP_ENV = process.env.APP_ENV || "local"; // local, dev, staging, prod

export const IS_LOCAL = APP_ENV === "local";
export const IS_DEV = APP_ENV === "dev";
export const IS_STAGING = APP_ENV === "staging";
export const IS_PROD = APP_ENV === "prod";

export const URLS = {
  API: IS_LOCAL ? `http://localhost:${API_PORT}` : `https://api.${APP_ENV === "prod" ? "" : APP_ENV + "."}app.com`,
  WEB: IS_LOCAL ? `http://localhost:${WEB_PORT}` : `https://${APP_ENV === "prod" ? "app" : APP_ENV}.app.com`,
};
