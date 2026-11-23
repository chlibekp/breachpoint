// Mirrors /shared data into the Godot project, because Godot exports can only package files under
// res://. The copies are committed so the client opens standalone; CI fails if they drift.
import { copyFileSync, mkdirSync, readdirSync, rmSync } from "node:fs";
import { join } from "node:path";
import { SHARED_DIR } from "../shared/src/config.ts";

const CLIENT = join(SHARED_DIR, "..", "client");
const jobs: { from: string; to: string }[] = [
  { from: join(SHARED_DIR, "config"), to: join(CLIENT, "data", "config") },
  { from: join(SHARED_DIR, "schemas"), to: join(CLIENT, "data", "schemas") },
  { from: join(SHARED_DIR, "tests", "protocol"), to: join(CLIENT, "tests", "data", "protocol") },
  { from: join(SHARED_DIR, "tests", "movement"), to: join(CLIENT, "tests", "data", "movement") },
  { from: join(SHARED_DIR, "tests", "weapons"), to: join(CLIENT, "tests", "data", "weapons") },
  { from: join(SHARED_DIR, "maps"), to: join(CLIENT, "data", "maps") },
];

let count = 0;
for (const { from, to } of jobs) {
  rmSync(to, { recursive: true, force: true });
  mkdirSync(to, { recursive: true });
  for (const name of readdirSync(from)) {
    if (!name.endsWith(".json") && !name.endsWith(".bin")) continue;
    copyFileSync(join(from, name), join(to, name));
    count++;
  }
}
console.log(`✓ synced ${count.toString()} shared files into client/`);
