import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { SSVError, extractSignedCallback } from "../src/callback.js";
import { AdMobSSVService } from "../src/service.js";
import { SQLiteRewardStore } from "../src/store.js";

const NOW = 2_000_000_000_000;
const USER_ID = "123e4567-e89b-42d3-a456-426614174000";
const ATTEMPT_ID = "123e4567-e89b-42d3-a456-426614174001";
const KEY_ID = "1916455855";

const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const publicKeyPEM = publicKey.export({ type: "spki", format: "pem" });

const policy = Object.freeze({
  adUnitID: "ca-app-pub-1234567890123456/1234567890",
  rewardAmount: "15",
  rewardItem: "minutes",
  maximumCallbackAgeMs: 10 * 60 * 1000,
  maximumFutureSkewMs: 60 * 1000,
  rollingWindowMs: 24 * 60 * 60 * 1000,
  maximumRewards: 4,
  retentionMs: 30 * 24 * 60 * 60 * 1000
});

function signedURL({
  transactionID = "18fa792de1bca816048293fc71035638",
  attemptID = ATTEMPT_ID,
  timestamp = NOW,
  rewardAmount = "15",
  rewardItem = "minutes",
  adUnit = "1234567890"
} = {}) {
  const pairs = [
    ["ad_network", "5450213213286189855"],
    ["ad_unit", adUnit],
    ["custom_data", attemptID],
    ["reward_amount", rewardAmount],
    ["reward_item", rewardItem],
    ["timestamp", String(timestamp)],
    ["transaction_id", transactionID],
    ["user_id", USER_ID]
  ];
  const signedContent = pairs
    .map(([name, value]) => `${name}=${encodeURIComponent(value)}`)
    .join("&");
  const signature = sign("sha256", Buffer.from(signedContent), privateKey).toString("base64url");
  return `/admob/ssv?${signedContent}&signature=${signature}&key_id=${KEY_ID}`;
}

function fixture({ now = () => NOW } = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), "aster-ssv-"));
  const store = new SQLiteRewardStore(path.join(directory, "ssv.sqlite"));
  const keyProvider = { getKey: async (keyID) => {
    assert.equal(keyID, KEY_ID);
    return publicKeyPEM;
  } };
  const service = new AdMobSSVService({
    keyProvider,
    store,
    policy,
    idHashKey: Buffer.alloc(32, 7),
    now
  });
  return {
    service,
    store,
    close() {
      store.close();
      rmSync(directory, { recursive: true, force: true });
    }
  };
}

test("accepts a valid signed callback exactly once", async () => {
  const context = fixture();
  try {
    assert.deepEqual(await context.service.process(signedURL()), { disposition: "accepted" });
    assert.deepEqual(await context.service.process(signedURL()), {
      disposition: "duplicate",
      originalDisposition: "accepted"
    });
  } finally {
    context.close();
  }
});

test("stores only keyed hashes of callback identifiers", async () => {
  const context = fixture();
  try {
    await context.service.process(signedURL());
    const row = context.store.database.prepare(`
      SELECT transaction_id_hash, user_id_hash, attempt_id_hash FROM ssv_transactions
    `).get();
    assert.match(row.transaction_id_hash, /^[0-9a-f]{64}$/);
    assert.match(row.user_id_hash, /^[0-9a-f]{64}$/);
    assert.match(row.attempt_id_hash, /^[0-9a-f]{64}$/);
    assert.notEqual(row.transaction_id_hash, "18fa792de1bca816048293fc71035638");
    assert.notEqual(row.user_id_hash, USER_ID);
    assert.notEqual(row.attempt_id_hash, ATTEMPT_ID);
  } finally {
    context.close();
  }
});

test("rejects any mutation after signing", async () => {
  const context = fixture();
  try {
    const mutated = signedURL().replace("reward_amount=15", "reward_amount=16");
    await assert.rejects(context.service.process(mutated), (error) => {
      assert.equal(error.code, "signature_mismatch");
      assert.equal(error.status, 403);
      return true;
    });
  } finally {
    context.close();
  }
});

test("requires signature and key_id to be the final parameters", () => {
  const callback = `${signedURL()}&extra=value`;
  assert.throws(() => extractSignedCallback(callback), (error) => {
    assert.equal(error.code, "invalid_signature_position");
    return true;
  });
});

test("rejects duplicated security parameters inside signed content", () => {
  const callback = signedURL().replace("&signature=", "&signature=duplicate&signature=");
  assert.throws(() => extractSignedCallback(callback), (error) => {
    assert.equal(error.code, "duplicate_security_parameter");
    return true;
  });
});

test("rejects a second Google transaction for the same client attempt", async () => {
  const context = fixture();
  try {
    await context.service.process(signedURL());
    const second = signedURL({ transactionID: "28fa792de1bca816048293fc71035638" });
    assert.deepEqual(await context.service.process(second), { disposition: "duplicate_attempt" });
  } finally {
    context.close();
  }
});

test("enforces four verified rewards in a rolling 24-hour window", async () => {
  const context = fixture();
  try {
    for (let index = 0; index < 5; index += 1) {
      const transactionID = (index + 1).toString(16).padStart(32, "0");
      const attemptID = `123e4567-e89b-42d3-a456-${String(426614174010 + index).padStart(12, "0")}`;
      const result = await context.service.process(signedURL({ transactionID, attemptID }));
      assert.equal(result.disposition, index < 4 ? "accepted" : "quota_exceeded");
    }
  } finally {
    context.close();
  }
});

test("rejects unexpected reward configuration and stale timestamps", async () => {
  const context = fixture();
  try {
    await assert.rejects(
      context.service.process(signedURL({ rewardItem: "coins" })),
      (error) => error instanceof SSVError && error.code === "unexpected_reward"
    );
    await assert.rejects(
      context.service.process(signedURL({ timestamp: NOW - policy.maximumCallbackAgeMs - 1 })),
      (error) => error instanceof SSVError && error.code === "stale_callback"
    );
    await assert.rejects(
      context.service.process(signedURL({ timestamp: NOW + policy.maximumFutureSkewMs + 1 })),
      (error) => error instanceof SSVError && error.code === "future_callback"
    );
    await assert.rejects(
      context.service.process(signedURL({ adUnit: "9999999999" })),
      (error) => error instanceof SSVError && error.code === "unexpected_ad_unit"
    );
  } finally {
    context.close();
  }
});

test("deletes transaction records after the configured retention period", async () => {
  let current = NOW;
  const context = fixture({ now: () => current });
  try {
    await context.service.process(signedURL());
    current += policy.retentionMs + 1;
    await context.service.process(signedURL({
      transactionID: "38fa792de1bca816048293fc71035638",
      attemptID: "123e4567-e89b-42d3-a456-426614174099",
      timestamp: current
    }));

    const row = context.store.database.prepare(
      "SELECT COUNT(*) AS count FROM ssv_transactions"
    ).get();
    assert.equal(row.count, 1);
  } finally {
    context.close();
  }
});
