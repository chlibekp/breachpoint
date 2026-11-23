// Regenerates shared/tests/protocol/vectors.json. Run only when messages.json changes on purpose;
// both the TS and GDScript test suites check their codecs against these bytes.
import { writeFileSync } from "node:fs";
import { join } from "node:path";
import { encode, type Message } from "../protocol/generated/protocol.ts";
import { messageToJson, toHex, type ProtocolVector } from "../protocol/vectors.ts";
import { SHARED_DIR } from "../src/config.ts";

const samples: Message[] = [
  { type: "Hello", protocolVersion: 1, token: "guest:κestrel-01", platform: "web" },
  { type: "AuthOk", playerId: 3, displayName: "Petr#1234", serverTick: 123456 },
  { type: "JoinMatch", ticket: "tkt_abc" },
  {
    type: "MatchState",
    matchId: "m-0001",
    map: "solstice",
    seed: 3735928559,
    roster: [
      { playerId: 0, name: "Alpha", team: 0, agent: "kestrel" },
      { playerId: 5, name: "Bravo", team: 1, agent: "vesper" },
    ],
  },
  {
    type: "Input",
    ackSnapshot: 9001,
    cmds: [
      { seq: 41, tick: 1000, buttons: 0b1011, yaw: 1.25, pitch: -0.3, weaponSlot: 1 },
      { seq: 42, tick: 1001, buttons: 0b1001, yaw: -2.75, pitch: 0.125, weaponSlot: 1 },
    ],
  },
  {
    type: "Snapshot",
    tick: 1002,
    baseTick: 998,
    lastProcessedSeq: 42,
    players: [
      {
        playerId: 1,
        pos: { x: 12.345, y: 0.25, z: -48.75 },
        vel: { x: 6.75, y: -3.125, z: 0 },
        yaw: 3.0,
        pitch: -1.2,
        flags: 0x0105,
        health: 100,
        shield: 50,
        weapon: 11,
      },
    ],
  },
  {
    type: "Fire",
    seq: 7,
    tick: 1003,
    interpTimeMs: 47,
    origin: { x: 1.125, y: 1.62, z: -3.5 },
    yaw: 0.5,
    pitch: 0.05,
    weapon: 11,
  },
  { type: "HitConfirm", shotSeq: 7, victimId: 6, hitZone: 0, damage: 160 },
  {
    type: "Damage",
    attackerId: 1,
    victimId: 6,
    amount: 40,
    hitZone: 1,
    fromPos: { x: -7.25, y: 1.5, z: 22.0 },
  },
  {
    type: "Kill",
    killerId: 1,
    victimId: 6,
    assisterIds: [2, 4],
    weapon: "saber",
    headshot: true,
    wallbang: false,
  },
  {
    type: "AbilityCast",
    seq: 3,
    tick: 1100,
    slot: 2,
    target: { x: 4, y: 0, z: 8.5 },
    yaw: -0.75,
    pitch: 0.2,
  },
  {
    type: "AbilityEvent",
    casterId: 2,
    ability: "starfall",
    event: 1,
    pos: { x: 4, y: 0, z: 8.5 },
    data: new Uint8Array([1, 2, 3, 250]),
  },
  { type: "BuyRequest", item: "saber" },
  { type: "BuyResult", item: "saber", ok: false, credits: 2100, reason: "insufficient_credits" },
  { type: "PlantStart", playerId: 3, site: 1, pos: { x: 30.5, y: 0.1, z: -12.25 } },
  { type: "DefuseStart", playerId: 7, resumeFromCheckpoint: true },
  { type: "RoundPhase", round: 13, phase: 2, endsAtTick: 64000, scoreAttack: 6, scoreDefense: 6 },
  { type: "Chat", playerId: 2, teamOnly: true, text: "Rotate B — smoke going out" },
  { type: "Ping", nonce: 77, clientTimeMs: 1234.5 },
  { type: "Pong", nonce: 77, clientTimeMs: 1234.5, serverTick: 4242 },
  { type: "Disconnect", reason: "server_shutdown" },
];

const vectors: ProtocolVector[] = samples.map((m) => ({
  message: messageToJson(m),
  hex: toHex(encode(m)),
}));
const out = join(SHARED_DIR, "tests", "protocol", "vectors.json");
writeFileSync(
  out,
  JSON.stringify(
    { comment: "Golden protocol vectors. Regenerate with npm run protocol:vectors.", vectors },
    null,
    2,
  ) + "\n",
);
console.log(`✓ wrote ${vectors.length} vectors → ${out}`);
