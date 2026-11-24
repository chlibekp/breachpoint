-- OAuth sign-in (spec §14.1: Google, Discord). One row per linked provider identity.
CREATE TABLE oauth_identities (
  provider    TEXT NOT NULL,
  subject     TEXT NOT NULL,            -- provider's stable user id
  account_id  BIGINT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  email       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (provider, subject)
);
CREATE INDEX oauth_identities_account ON oauth_identities(account_id);
