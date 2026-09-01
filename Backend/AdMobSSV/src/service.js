import {
  SSVError,
  extractSignedCallback,
  parseVerifiedPayload,
  rawQueryHash,
  validatePayload,
  verifySignedCallback
} from "./callback.js";
import { createHmac } from "node:crypto";

export class AdMobSSVService {
  constructor({ keyProvider, store, policy, idHashKey, now = Date.now }) {
    if (!keyProvider || !store || !Buffer.isBuffer(idHashKey) || idHashKey.length < 32) {
      throw new TypeError("A key provider, persistent reward store, and 256-bit ID hash key are required.");
    }
    this.keyProvider = keyProvider;
    this.store = store;
    this.policy = policy;
    this.idHashKey = idHashKey;
    this.now = now;
  }

  async process(rawURL) {
    const envelope = extractSignedCallback(rawURL);
    const publicKey = await this.keyProvider.getKey(envelope.keyID);
    verifySignedCallback(envelope, publicKey);

    const payload = parseVerifiedPayload(envelope.signedContent);
    const receivedAtMs = this.now();
    validatePayload(payload, this.policy, receivedAtMs);

    try {
      const storagePayload = {
        ...payload,
        transactionID: this.hashIdentifier("transaction", payload.transactionID),
        userID: this.hashIdentifier("user", payload.userID),
        attemptID: this.hashIdentifier("attempt", payload.attemptID)
      };
      return this.store.recordVerified(storagePayload, {
        receivedAtMs,
        rollingWindowMs: this.policy.rollingWindowMs,
        maximumRewards: this.policy.maximumRewards,
        retentionMs: this.policy.retentionMs,
        rawQuerySHA256: rawQueryHash(envelope.rawQuery)
      });
    } catch {
      throw new SSVError("storage_failure", "Unable to persist verified callback.", {
        status: 503,
        retryable: true
      });
    }
  }

  hashIdentifier(domain, value) {
    return createHmac("sha256", this.idHashKey)
      .update(domain, "utf8")
      .update("\0", "utf8")
      .update(value, "utf8")
      .digest("hex");
  }
}
