// QA helper: plays a 10-bot match headlessly and writes its replay.
// Usage: npx tsx server/scripts/make-replay.ts <outDir> [map] [roundsToWin]
import { Match } from "../src/match/match.ts";

const [dir = "replays", map = "solstice", rounds = "2"] = process.argv.slice(2);
const m = new Match({
  matchId: `qa-${map}`,
  map,
  mode: "unrated",
  seed: 11,
  fillBots: true,
  roundsToWin: Number(rounds),
  phaseScale: 0.5,
  replayDir: dir,
});
m.startManual();
let ticks = 0;
while (!m.finished && ticks < 64 * 60 * 40) {
  m.step();
  ticks++;
}
await m.closeReplay();
console.log(`wrote ${dir}/qa-${map}.bpr (${ticks} ticks, score ${m.score.join(":")})`);
