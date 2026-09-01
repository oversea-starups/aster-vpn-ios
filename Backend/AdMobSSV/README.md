# Aster AdMob SSV verifier

Production-oriented, cloud-neutral Node service for validating Aster rewarded-ad server-side verification callbacks. It verifies the untouched callback query with Google's ECDSA key, validates Aster's ad/reward contract, records every verified Google transaction in persistent SQLite through the version-pinned `better-sqlite3` driver, deduplicates transaction and client-attempt IDs, and enforces four accepted rewards per anonymous installation in a rolling 24-hour window. Callback identifiers are domain-separated HMAC-SHA256 values at rest, never raw UUIDs or Google transaction IDs.

The iOS client still grants time immediately in Google's earned-reward callback for responsive UX. This service is the reconciliation and abuse-audit authority; it does not receive early-closed ads, so the six-presentation limit remains in the client's Keychain ledger.

## Required production configuration

```text
SSV_DATABASE_PATH=/absolute/persistent/path/admob-ssv.sqlite
SSV_ID_HASH_KEY=<64 hexadecimal characters from a cryptographically secure generator>
ADMOB_REWARDED_AD_UNIT_ID=ca-app-pub-<publisher>/<ad-unit>
ADMOB_REWARD_AMOUNT=15
ADMOB_REWARD_ITEM=minutes
HOST=127.0.0.1
PORT=8787
```

Optional bounds default to `SSV_MAX_REWARDS_PER_24H=4`, `SSV_MAX_CALLBACK_AGE_SECONDS=600`, `SSV_MAX_FUTURE_SKEW_SECONDS=60`, and `SSV_RETENTION_DAYS=30`. Retention is enforced during verified callback transactions and cannot be configured above 365 days.

Run the service behind an HTTPS reverse proxy with durable storage and encrypted backups. Configure the AdMob callback as `https://<public-host>/admob/ssv`. Keep `SSV_ID_HASH_KEY` stable in a secret manager for at least the configured retention period. The process refuses in-memory/relative database paths and refuses to start without the ad, reward, storage, and hashing contract.

## Verification

```bash
cd Backend/AdMobSSV
npm run check
npm test
```

Tests generate a real P-256 key pair and DER ECDSA signatures, then use a temporary on-disk SQLite database. Production startup always uses Google's fixed key endpoint and requires persistent storage; it contains no in-memory fallback.

Operational logs contain only outcome codes, never raw callback URLs, anonymous user IDs, attempt IDs, transaction IDs, IP addresses, or ad query values.

## Container

The included image uses an exact Node version, installs the lockfile with `npm ci`, runs as the unprivileged `node` user, and exposes a health check. Mount durable storage at `/data` and set `SSV_DATABASE_PATH=/data/admob-ssv.sqlite`.

```bash
docker build -t aster-admob-ssv:1.0.0 .
```

Supply all secrets through the deployment platform; never bake `SSV_ID_HASH_KEY` or AdMob configuration into the image. TLS termination, request-rate controls, encrypted backups, monitoring, and public DNS belong to the selected hosting environment.
