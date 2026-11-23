// Loads and validates every shared config file against its JSON Schema, plus the
// cross-field rules a schema cannot express. Used by the server at startup and by CI.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Ajv2020 } from "ajv/dist/2020.js";

export const SHARED_DIR = join(dirname(fileURLToPath(import.meta.url)), "..");
export const CONFIG_NAMES = [
  "weapons",
  "agents",
  "economy",
  "movement",
  "match",
  "quality",
] as const;
export type ConfigName = (typeof CONFIG_NAMES)[number];

export interface ConfigIssue {
  file: string;
  message: string;
}

function readJson(path: string): unknown {
  return JSON.parse(readFileSync(path, "utf8")) as unknown;
}

export function loadRawConfig(name: ConfigName, dir: string = SHARED_DIR): unknown {
  return readJson(join(dir, "config", `${name}.json`));
}

export function validateConfigs(dir: string = SHARED_DIR): ConfigIssue[] {
  const ajv = new Ajv2020({ allErrors: true, strict: true, strictTypes: false });
  const issues: ConfigIssue[] = [];
  const data: Partial<Record<ConfigName, unknown>> = {};
  for (const name of CONFIG_NAMES) {
    const schema = readJson(join(dir, "schemas", `${name}.schema.json`)) as object;
    const value = loadRawConfig(name, dir);
    const validate = ajv.compile(schema);
    if (!validate(value)) {
      for (const err of validate.errors ?? []) {
        issues.push({
          file: `${name}.json`,
          message: `${err.instancePath || "/"} ${err.message ?? ""}`,
        });
      }
    } else {
      data[name] = value;
    }
  }
  issues.push(...crossChecks(data));
  return issues;
}

interface WeaponLike {
  id: string;
  magazine: number;
  fireMode: string;
  burst: unknown;
  recoil: { pattern: unknown[] };
  class: string;
}
interface AgentLike {
  id: string;
  abilities: { slot: string; ultPoints?: number }[];
}

function uniqueIds(file: string, ids: string[]): ConfigIssue[] {
  const seen = new Set<string>();
  const out: ConfigIssue[] = [];
  for (const id of ids) {
    if (seen.has(id)) out.push({ file, message: `duplicate id "${id}"` });
    seen.add(id);
  }
  return out;
}

function crossChecks(data: Partial<Record<ConfigName, unknown>>): ConfigIssue[] {
  const out: ConfigIssue[] = [];
  const weapons = (data.weapons as { weapons: WeaponLike[] } | undefined)?.weapons;
  if (weapons) {
    out.push(
      ...uniqueIds(
        "weapons.json",
        weapons.map((w) => w.id),
      ),
    );
    for (const w of weapons) {
      if (w.class !== "melee" && w.recoil.pattern.length < Math.min(w.magazine, 1)) {
        out.push({ file: "weapons.json", message: `${w.id}: recoil pattern is empty` });
      }
      if (w.fireMode === "burst" && w.burst === null) {
        out.push({ file: "weapons.json", message: `${w.id}: burst fireMode needs burst settings` });
      }
    }
  }
  const agents = (data.agents as { agents: AgentLike[] } | undefined)?.agents;
  if (agents) {
    out.push(
      ...uniqueIds(
        "agents.json",
        agents.map((a) => a.id),
      ),
    );
    for (const a of agents) {
      const slots = a.abilities.map((ab) => ab.slot).join("");
      if (slots !== "CQEX")
        out.push({
          file: "agents.json",
          message: `${a.id}: abilities must be ordered C,Q,E,X (got ${slots})`,
        });
      const ult = a.abilities.find((ab) => ab.slot === "X");
      if (ult?.ultPoints === undefined)
        out.push({ file: "agents.json", message: `${a.id}: X ability needs ultPoints` });
    }
  }
  const quality = data.quality as { tiers: { id: string; index: number }[] } | undefined;
  if (quality) {
    quality.tiers.forEach((t, i) => {
      if (t.index !== i)
        out.push({
          file: "quality.json",
          message: `tier ${t.id} index ${t.index} != position ${i}`,
        });
    });
  }
  return out;
}
