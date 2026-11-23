import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["shared/tests/**/*.test.ts", "server/tests/**/*.test.ts"],
    testTimeout: 15000,
    // Integration suites share one test database + Redis; run files one at a time.
    fileParallelism: false,
  },
});
