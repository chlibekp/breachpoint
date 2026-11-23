import { validateConfigs } from "../src/config.ts";

const issues = validateConfigs();
if (issues.length > 0) {
  for (const issue of issues) console.error(`✗ ${issue.file}: ${issue.message}`);
  process.exit(1);
}
console.log("✓ shared configs valid");
