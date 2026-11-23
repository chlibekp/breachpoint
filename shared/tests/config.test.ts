import { describe, expect, it } from "vitest";
import { loadRawConfig, validateConfigs } from "../src/config.ts";

interface Weapon {
  id: string;
  class: string;
  cost: number;
  damage: { body: number; headMult: number; pellets: number };
}

describe("shared configs", () => {
  it("validate against their schemas and cross-checks", () => {
    expect(validateConfigs()).toEqual([]);
  });

  it("ship the 15 launch weapons plus the knife", () => {
    const { weapons } = loadRawConfig("weapons") as { weapons: Weapon[] };
    expect(weapons).toHaveLength(16);
    expect(weapons.filter((w) => w.class === "melee")).toHaveLength(1);
  });

  it("let core rifles one-tap a heavy-shielded head (150 HP)", () => {
    const { weapons } = loadRawConfig("weapons") as { weapons: Weapon[] };
    for (const id of ["saber", "specter"]) {
      const w = weapons.find((x) => x.id === id)!;
      expect(w.damage.body * w.damage.headMult).toBeGreaterThanOrEqual(150);
    }
  });

  it("ship eight agents, two per role", () => {
    const { agents } = loadRawConfig("agents") as { agents: { role: string }[] };
    expect(agents).toHaveLength(8);
    for (const role of ["vanguard", "shroud", "seeker", "warden"]) {
      expect(agents.filter((a) => a.role === role)).toHaveLength(2);
    }
  });
});
