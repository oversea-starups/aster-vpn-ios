import assert from "node:assert/strict";
import { generateKeyPairSync } from "node:crypto";
import test from "node:test";
import { AdMobPublicKeyProvider, ADMOB_KEY_URL } from "../src/key-provider.js";

const { publicKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
const pem = publicKey.export({ type: "spki", format: "pem" });

test("caches Google verification keys but never beyond 24 hours", async () => {
  let now = 2_000_000_000_000;
  let requests = 0;
  const fetcher = async (url) => {
    requests += 1;
    assert.equal(url, ADMOB_KEY_URL);
    return {
      ok: true,
      text: async () => JSON.stringify({ keys: [{ keyId: 123, pem }] })
    };
  };
  const provider = new AdMobPublicKeyProvider({
    fetcher,
    now: () => now,
    cacheAgeMs: 48 * 60 * 60 * 1000
  });

  assert.equal(await provider.getKey("123"), pem);
  assert.equal(await provider.getKey("123"), pem);
  assert.equal(requests, 1);

  now += 24 * 60 * 60 * 1000;
  assert.equal(await provider.getKey("123"), pem);
  assert.equal(requests, 2);
});

test("coalesces concurrent key downloads", async () => {
  let requests = 0;
  const provider = new AdMobPublicKeyProvider({
    fetcher: async () => {
      requests += 1;
      return {
        ok: true,
        text: async () => JSON.stringify({ keys: [{ keyId: 456, pem }] })
      };
    }
  });

  const keys = await Promise.all([provider.getKey("456"), provider.getKey("456")]);
  assert.deepEqual(keys, [pem, pem]);
  assert.equal(requests, 1);
});

test("rejects key documents that do not contain EC keys", async () => {
  const { publicKey: rsaPublicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  const rsaPEM = rsaPublicKey.export({ type: "spki", format: "pem" });
  const provider = new AdMobPublicKeyProvider({
    fetcher: async () => ({
      ok: true,
      text: async () => JSON.stringify({ keys: [{ keyId: 789, pem: rsaPEM }] })
    })
  });

  await assert.rejects(provider.getKey("789"), (error) => {
    assert.equal(error.code, "invalid_key_document");
    return true;
  });
});
