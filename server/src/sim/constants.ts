// Pure simulation constants derived from shared config. The sim package must stay free of I/O
// so it can be unit-tested, replayed, and mirrored in GDScript (client/scripts/sim/).
export const TICK_RATE = 64;
export const TICK_DT = 1 / TICK_RATE;
