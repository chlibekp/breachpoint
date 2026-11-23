# BREACHPOINT — agent guide

Start every session by reading `docs/PROGRESS.md` (status, open problems, next steps, environment
setup). The full spec is `docs/prompt.md`; record any choice it leaves open in `docs/DECISIONS.md`.

Rules that matter most:

- Work milestone by milestone (spec §18). Finish, report with screenshots + perf + open problems, and
  wait for owner approval before the next one. Ask before changing spec sections 2, 4 or 10.
- Data lives in `shared/config/*.json` (+ schemas). Never hard-code balance numbers. After edits run
  `npm run sync:client`. Protocol changes go in `shared/protocol/messages.json` then
  `npm run protocol:gen` (and `npm run protocol:vectors` if the wire format changed on purpose).
- Original IP only: no names, assets, fonts, sounds or layouts from other games. Log every
  third-party asset in `docs/CREDITS.md`. Grey-box geometry must be named `BLOCKOUT_*`.
- GDScript is statically typed; warnings are errors. TypeScript is strict, no `any`.
- Before committing: `npm run ci` and `GODOT_BIN=… npm run godot:test` must pass.
- Update `docs/PROGRESS.md` (checklist + session log) before ending a session.
- The owner wants commits pushed to `main` as well as the working branch.
