// Shared by every master shader (spec 5.5). quality_tier: 0 = web, 1 = low, 2 = medium, 3 = high, 4 = ultra.
// Guard expensive paths with `if (quality_tier >= QUALITY_MEDIUM)`; never rely on Forward+-only built-ins.
global uniform int quality_tier;
const int QUALITY_WEB = 0;
const int QUALITY_LOW = 1;
const int QUALITY_MEDIUM = 2;
const int QUALITY_HIGH = 3;
const int QUALITY_ULTRA = 4;
