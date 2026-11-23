// Glicko-2 (spec §14.1: hidden MMR). Standard algorithm (Glickman 2012), one rating period per match.
export interface Glicko {
  rating: number;
  rd: number;
  volatility: number;
}

const SCALE = 173.7178;
const TAU = 0.5;

/** Updates `p` against a set of opponents with scores 1 (win), 0.5 (draw), 0 (loss). */
export function glicko2(
  p: Glicko,
  opponents: { rating: number; rd: number; score: number }[],
): Glicko {
  if (opponents.length === 0) {
    const phi = p.rd / SCALE;
    return { ...p, rd: Math.min(350, Math.sqrt(phi * phi + p.volatility * p.volatility) * SCALE) };
  }
  const mu = (p.rating - 1500) / SCALE;
  const phi = p.rd / SCALE;
  const g = (ph: number): number => 1 / Math.sqrt(1 + (3 * ph * ph) / (Math.PI * Math.PI));
  const E = (m: number, mj: number, pj: number): number => 1 / (1 + Math.exp(-g(pj) * (m - mj)));
  let vInv = 0;
  let deltaSum = 0;
  for (const o of opponents) {
    const mj = (o.rating - 1500) / SCALE;
    const pj = o.rd / SCALE;
    const e = E(mu, mj, pj);
    vInv += g(pj) * g(pj) * e * (1 - e);
    deltaSum += g(pj) * (o.score - e);
  }
  const v = 1 / vInv;
  const delta = v * deltaSum;
  // Volatility iteration (Illinois algorithm).
  const a = Math.log(p.volatility * p.volatility);
  const f = (x: number): number =>
    (Math.exp(x) * (delta * delta - phi * phi - v - Math.exp(x))) /
      (2 * (phi * phi + v + Math.exp(x)) ** 2) -
    (x - a) / (TAU * TAU);
  let A = a;
  let B: number;
  if (delta * delta > phi * phi + v) B = Math.log(delta * delta - phi * phi - v);
  else {
    let k = 1;
    while (f(a - k * TAU) < 0) k++;
    B = a - k * TAU;
  }
  let fA = f(A);
  let fB = f(B);
  for (let i = 0; i < 100 && Math.abs(B - A) > 1e-6; i++) {
    const C = A + ((A - B) * fA) / (fB - fA);
    const fC = f(C);
    if (fC * fB <= 0) {
      A = B;
      fA = fB;
    } else fA /= 2;
    B = C;
    fB = fC;
  }
  const sigma = Math.exp(A / 2);
  const phiStar = Math.sqrt(phi * phi + sigma * sigma);
  const phiNew = 1 / Math.sqrt(1 / (phiStar * phiStar) + 1 / v);
  const muNew = mu + phiNew * phiNew * deltaSum;
  return { rating: muNew * SCALE + 1500, rd: Math.max(30, phiNew * SCALE), volatility: sigma };
}
