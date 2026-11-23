-- BREACHPOINT core schema (spec §14.2). Applied in order by server/src/services/db.ts.
CREATE TABLE accounts (
  id            BIGSERIAL PRIMARY KEY,
  email         TEXT UNIQUE,                 -- NULL for guest accounts
  password_hash TEXT,                        -- argon2id
  name          TEXT NOT NULL,
  tag           TEXT NOT NULL,               -- Name#1234
  guest         BOOLEAN NOT NULL DEFAULT FALSE,
  level         INTEGER NOT NULL DEFAULT 1,
  xp            INTEGER NOT NULL DEFAULT 0,
  settings      JSONB NOT NULL DEFAULT '{}'::jsonb,
  loadout       JSONB NOT NULL DEFAULT '{}'::jsonb,
  owned_skins   JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (name, tag)
);

CREATE TABLE refresh_tokens (
  id          BIGSERIAL PRIMARY KEY,
  account_id  BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  token_hash  TEXT NOT NULL UNIQUE,          -- sha256 of the opaque token
  family      UUID NOT NULL,                 -- rotation family; reuse of a rotated token revokes the family
  revoked     BOOLEAN NOT NULL DEFAULT FALSE,
  expires_at  TIMESTAMPTZ NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_account ON refresh_tokens(account_id);

CREATE TABLE ratings (
  account_id  BIGINT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
  rating      DOUBLE PRECISION NOT NULL DEFAULT 1500,
  rd          DOUBLE PRECISION NOT NULL DEFAULT 350,
  volatility  DOUBLE PRECISION NOT NULL DEFAULT 0.06,
  games       INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE matches (
  id          TEXT PRIMARY KEY,
  mode        TEXT NOT NULL,
  map         TEXT NOT NULL,
  started_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at    TIMESTAMPTZ,
  score_a     INTEGER NOT NULL DEFAULT 0,
  score_b     INTEGER NOT NULL DEFAULT 0,
  winner      INTEGER,                       -- team index or NULL for draw
  rounds      JSONB NOT NULL DEFAULT '[]'::jsonb
);

CREATE TABLE match_players (
  match_id    TEXT NOT NULL REFERENCES matches(id) ON DELETE CASCADE,
  account_id  BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
  name        TEXT NOT NULL,
  team        INTEGER NOT NULL,
  agent       TEXT NOT NULL,
  kills       INTEGER NOT NULL DEFAULT 0,
  deaths      INTEGER NOT NULL DEFAULT 0,
  assists     INTEGER NOT NULL DEFAULT 0,
  score       INTEGER NOT NULL DEFAULT 0,
  rating_delta DOUBLE PRECISION,
  PRIMARY KEY (match_id, name)
);
CREATE INDEX match_players_account ON match_players(account_id);

CREATE TABLE reports (
  id          BIGSERIAL PRIMARY KEY,
  reporter_id BIGINT REFERENCES accounts(id) ON DELETE SET NULL,
  target_name TEXT NOT NULL,
  match_id    TEXT,
  reason      TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
