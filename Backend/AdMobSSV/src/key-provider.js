import { createPublicKey } from "node:crypto";
import { SSVError } from "./callback.js";

export const ADMOB_KEY_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
const MAX_GOOGLE_CACHE_AGE_MS = 24 * 60 * 60 * 1000;

export class AdMobPublicKeyProvider {
  constructor({
    fetcher = globalThis.fetch,
    now = Date.now,
    cacheAgeMs = MAX_GOOGLE_CACHE_AGE_MS,
    requestTimeoutMs = 5_000
  } = {}) {
    if (typeof fetcher !== "function") {
      throw new TypeError("A fetch implementation is required.");
    }
    this.fetcher = fetcher;
    this.now = now;
    this.cacheAgeMs = Math.min(Math.max(1, cacheAgeMs), MAX_GOOGLE_CACHE_AGE_MS);
    this.requestTimeoutMs = requestTimeoutMs;
    this.keys = new Map();
    this.fetchedAt = 0;
    this.refreshPromise = null;
    this.lastUnknownKeyRefreshAt = 0;
  }

  async getKey(keyID) {
    const current = this.now();
    const cacheWasFresh = this.keys.size > 0 && current - this.fetchedAt < this.cacheAgeMs;
    if (!cacheWasFresh) {
      await this.refresh();
    }

    let key = this.keys.get(String(keyID));
    if (
      !key &&
      cacheWasFresh &&
      current - this.lastUnknownKeyRefreshAt >= 60_000
    ) {
      this.lastUnknownKeyRefreshAt = current;
      await this.refresh();
      key = this.keys.get(String(keyID));
    }

    if (!key) {
      throw new SSVError("unknown_key_id", "No AdMob verification key matches key_id.", {
        status: 403
      });
    }
    return key;
  }

  async refresh() {
    if (this.refreshPromise) {
      return this.refreshPromise;
    }
    this.refreshPromise = this.downloadKeys();
    try {
      await this.refreshPromise;
    } finally {
      this.refreshPromise = null;
    }
  }

  async downloadKeys() {
    let response;
    try {
      response = await this.fetcher(ADMOB_KEY_URL, {
        method: "GET",
        headers: { accept: "application/json" },
        signal: AbortSignal.timeout(this.requestTimeoutMs)
      });
    } catch {
      throw new SSVError("key_download_failed", "Unable to download AdMob verification keys.", {
        status: 503,
        retryable: true
      });
    }

    if (!response?.ok) {
      throw new SSVError("key_download_failed", "AdMob key server returned an error.", {
        status: 503,
        retryable: true
      });
    }

    let text;
    try {
      text = await response.text();
    } catch {
      throw new SSVError("key_download_failed", "Unable to read AdMob verification keys.", {
        status: 503,
        retryable: true
      });
    }
    if (text.length === 0 || text.length > 1_000_000) {
      throw new SSVError("invalid_key_document", "AdMob key document size is invalid.", {
        status: 503,
        retryable: true
      });
    }

    let document;
    try {
      document = JSON.parse(text);
    } catch {
      throw new SSVError("invalid_key_document", "AdMob key document is invalid JSON.", {
        status: 503,
        retryable: true
      });
    }

    const nextKeys = new Map();
    if (!Array.isArray(document.keys)) {
      throw new SSVError("invalid_key_document", "AdMob key document has no keys.", {
        status: 503,
        retryable: true
      });
    }
    for (const item of document.keys) {
      if (!Number.isInteger(item?.keyId) || typeof item?.pem !== "string") {
        continue;
      }
      try {
        const key = createPublicKey(item.pem);
        if (key.asymmetricKeyType !== "ec") {
          continue;
        }
        nextKeys.set(String(item.keyId), item.pem);
      } catch {
        continue;
      }
    }
    if (nextKeys.size === 0) {
      throw new SSVError("invalid_key_document", "AdMob key document has no valid keys.", {
        status: 503,
        retryable: true
      });
    }

    this.keys = nextKeys;
    this.fetchedAt = this.now();
  }
}
