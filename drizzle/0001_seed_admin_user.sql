-- Seed the initial admin account.
--
-- The password hash below is scrypt(<password>, random-salt) in the format
-- produced by lib/auth/password.ts (scrypt$<saltHex>$<derivedHex>). The
-- plaintext password is never stored in the repo or the database.
--
-- Idempotent: ON CONFLICT keeps re-runs safe and never clobbers a password
-- that has since been changed through the app.
INSERT INTO "users" ("email", "password_hash", "first_name", "last_name")
VALUES (
  'wpcarlson@gmail.com',
  'scrypt$17eeeb01cdb2ff7993b750c7f8253aea$40d113530d8e7960c9acd79dcccb4010cfb58853ed1a855932bc337a7f979e3cb842eeca84bc3d6faea3ff0ac0d784451b2185b22242bcbed07589f1a5e24392',
  'Billy',
  'Carlson'
)
ON CONFLICT ("email") DO NOTHING;
