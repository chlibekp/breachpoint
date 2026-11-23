// Loads exported map data (spec §13.2): collision boxes + gameplay meta from /shared/maps.
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { SHARED_DIR } from "@breachpoint/shared/config";
import { parseCollision, type World } from "../sim/collision.ts";

export type V3 = [number, number, number];

export interface MapMeta {
  map: string;
  spawns: { attack: { pos: V3; yaw: number }[]; defense: { pos: V3; yaw: number }[] };
  sites: { name: string; center: V3; size: V3 }[];
  plantZones: { site: string; center: V3; size: V3 }[];
  buyZones: { team: string; center: V3; size: V3 }[];
  riftOrbs: V3[];
  callouts: { name: string; center: V3; size: V3 }[];
  barriers?: { team: string; center: V3; size: V3 }[];
  /** Walkable lane rectangles for bot navigation. */
  nav?: { name: string; center: V3; size: V3 }[];
}

export function loadWorld(mapId: string): World {
  return parseCollision(
    new Uint8Array(readFileSync(join(SHARED_DIR, "maps", `${mapId}.collision.bin`))),
  );
}

export function loadMeta(mapId: string): MapMeta {
  return JSON.parse(
    readFileSync(join(SHARED_DIR, "maps", `${mapId}.meta.json`), "utf8"),
  ) as MapMeta;
}

export function inBox(x: number, y: number, z: number, center: V3, size: V3): boolean {
  return (
    Math.abs(x - center[0]) <= size[0] / 2 &&
    Math.abs(y - center[1]) <= size[1] / 2 + 1 &&
    Math.abs(z - center[2]) <= size[2] / 2
  );
}
