import Database from "better-sqlite3";
import { chmodSync } from "node:fs";

export class SQLiteRewardStore {
  constructor(databasePath) {
    if (typeof databasePath !== "string" || databasePath.length === 0 || databasePath === ":memory:") {
      throw new TypeError("A persistent SQLite database path is required.");
    }

    this.database = new Database(databasePath);
    chmodSync(databasePath, 0o600);
    const schemaVersion = this.database.pragma("user_version", { simple: true });
    if (schemaVersion !== 0 && schemaVersion !== 1) {
      this.database.close();
      throw new Error(`Unsupported SSV database schema version: ${schemaVersion}`);
    }
    this.database.exec(`
      PRAGMA journal_mode = WAL;
      PRAGMA synchronous = FULL;
      PRAGMA busy_timeout = 5000;
      CREATE TABLE IF NOT EXISTS ssv_transactions (
        transaction_id_hash TEXT PRIMARY KEY,
        user_id_hash TEXT NOT NULL,
        attempt_id_hash TEXT NOT NULL,
        rewarded_at_ms INTEGER NOT NULL,
        received_at_ms INTEGER NOT NULL,
        status TEXT NOT NULL CHECK (status IN ('accepted', 'duplicate_attempt', 'quota_exceeded')),
        ad_unit TEXT NOT NULL,
        reward_amount TEXT NOT NULL,
        reward_item TEXT NOT NULL,
        raw_query_sha256 TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_ssv_user_rewarded
        ON ssv_transactions(user_id_hash, rewarded_at_ms)
        WHERE status = 'accepted';
      CREATE INDEX IF NOT EXISTS idx_ssv_attempt
        ON ssv_transactions(user_id_hash, attempt_id_hash, status);
      PRAGMA user_version = 1;
    `);

    this.findTransaction = this.database.prepare(`
      SELECT status FROM ssv_transactions WHERE transaction_id_hash = ?
    `);
    this.findAcceptedAttempt = this.database.prepare(`
      SELECT transaction_id_hash FROM ssv_transactions
      WHERE user_id_hash = ? AND attempt_id_hash = ? AND status = 'accepted'
      LIMIT 1
    `);
    this.countRecentAccepted = this.database.prepare(`
      SELECT COUNT(*) AS count FROM ssv_transactions
      WHERE user_id_hash = ? AND status = 'accepted' AND rewarded_at_ms > ?
    `);
    this.insertTransaction = this.database.prepare(`
      INSERT INTO ssv_transactions (
        transaction_id_hash, user_id_hash, attempt_id_hash, rewarded_at_ms, received_at_ms,
        status, ad_unit, reward_amount, reward_item, raw_query_sha256
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    this.deleteExpired = this.database.prepare(`
      DELETE FROM ssv_transactions WHERE received_at_ms < ?
    `);
  }

  recordVerified(
    payload,
    { receivedAtMs, rollingWindowMs, maximumRewards, retentionMs, rawQuerySHA256 }
  ) {
    this.database.exec("BEGIN IMMEDIATE");
    try {
      this.deleteExpired.run(receivedAtMs - retentionMs);
      const existing = this.findTransaction.get(payload.transactionID);
      if (existing) {
        this.database.exec("COMMIT");
        return { disposition: "duplicate", originalDisposition: existing.status };
      }

      let disposition = "accepted";
      if (this.findAcceptedAttempt.get(payload.userID, payload.attemptID)) {
        disposition = "duplicate_attempt";
      } else {
        const windowStart = receivedAtMs - rollingWindowMs;
        const row = this.countRecentAccepted.get(payload.userID, windowStart);
        if (Number(row.count) >= maximumRewards) {
          disposition = "quota_exceeded";
        }
      }

      this.insertTransaction.run(
        payload.transactionID,
        payload.userID,
        payload.attemptID,
        payload.rewardedAtMs,
        receivedAtMs,
        disposition,
        payload.adUnit,
        payload.rewardAmount,
        payload.rewardItem,
        rawQuerySHA256
      );
      this.database.exec("COMMIT");
      return { disposition };
    } catch (error) {
      this.database.exec("ROLLBACK");
      throw error;
    }
  }

  close() {
    this.database.close();
  }
}
