#!/bin/sh
set -eu
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=service_key_hash="$SERVICE_API_KEY_HASH" <<'SQL'
INSERT INTO api_keys (name, key_hash, is_active)
VALUES ('evaluation-local', :'service_key_hash', true)
ON CONFLICT (key_hash) DO NOTHING;
SQL
