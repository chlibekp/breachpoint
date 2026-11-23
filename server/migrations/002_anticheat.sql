-- Statistical anti-cheat review flags (spec §14.3). Written with the match result; a reviewer
-- watches the match replay (kept 14 days) before acting. Never used for automatic bans.
CREATE TABLE anticheat_flags (
  id          BIGSERIAL PRIMARY KEY,
  account_id  BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  match_id    TEXT NOT NULL,
  kind        TEXT NOT NULL,
  value       DOUBLE PRECISION NOT NULL,
  samples     INTEGER NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX anticheat_flags_account ON anticheat_flags(account_id, created_at DESC);
CREATE INDEX reports_target ON reports(target_name, created_at DESC);
