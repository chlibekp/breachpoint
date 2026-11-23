// worker_threads entry: one match per worker (spec 13.1). The parent posts
// {cmd:"start"|"stop"|"stats"}; the worker answers with tick statistics.
import { parentPort, workerData } from "node:worker_threads";
import { Match, type MatchOptions } from "./match.ts";

type Command = { cmd: "start" } | { cmd: "stop" } | { cmd: "stats" };

const match = new Match(workerData as MatchOptions);

parentPort?.on("message", (msg: Command) => {
  switch (msg.cmd) {
    case "start":
      match.start();
      break;
    case "stop":
      match.stop();
      parentPort?.postMessage({ type: "stopped", tick: match.tick });
      break;
    case "stats":
      parentPort?.postMessage({ type: "stats", tick: match.tick, stats: match.loop.stats });
      break;
  }
});
