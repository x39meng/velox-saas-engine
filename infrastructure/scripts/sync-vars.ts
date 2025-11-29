import { SERVICE_NAMES, API_PORT, WEB_PORT } from "../../packages/config/src/index.ts";
import { writeFileSync } from "fs";
import { join } from "path";

const tfvars = {
  service_names: SERVICE_NAMES,
  ports: {
    api: API_PORT,
    web: WEB_PORT,
  },
};

const devPath = join(__dirname, "../envs/dev/terraform.tfvars.json");
const stagingPath = join(__dirname, "../envs/staging/terraform.tfvars.json");
const prodPath = join(__dirname, "../envs/prod/terraform.tfvars.json");

writeFileSync(devPath, JSON.stringify(tfvars, null, 2));
writeFileSync(stagingPath, JSON.stringify(tfvars, null, 2));
writeFileSync(prodPath, JSON.stringify(tfvars, null, 2));

console.log("Synced variables to Terraform");
