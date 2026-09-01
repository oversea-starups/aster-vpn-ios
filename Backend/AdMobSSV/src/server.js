import http from "node:http";
import path from "node:path";
import { SSVError, normalizeDecimal } from "./callback.js";
import { AdMobPublicKeyProvider } from "./key-provider.js";
import { AdMobSSVService } from "./service.js";
import { SQLiteRewardStore } from "./store.js";

const required = (name) => {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is required.`);
  }
  return value;
};

const positiveInteger = (name, fallback) => {
  const value = Number(process.env[name] ?? fallback);
  if (!Number.isSafeInteger(value) || value <= 0) {
    throw new Error(`${name} must be a positive integer.`);
  }
  return value;
};

const databasePath = required("SSV_DATABASE_PATH");
if (!path.isAbsolute(databasePath) || databasePath === ":memory:") {
  throw new Error("SSV_DATABASE_PATH must be an absolute persistent path.");
}

const policy = Object.freeze({
  adUnitID: required("ADMOB_REWARDED_AD_UNIT_ID"),
  rewardAmount: normalizeDecimal(required("ADMOB_REWARD_AMOUNT")),
  rewardItem: required("ADMOB_REWARD_ITEM"),
  maximumCallbackAgeMs: positiveInteger("SSV_MAX_CALLBACK_AGE_SECONDS", 600) * 1000,
  maximumFutureSkewMs: positiveInteger("SSV_MAX_FUTURE_SKEW_SECONDS", 60) * 1000,
  rollingWindowMs: 24 * 60 * 60 * 1000,
  maximumRewards: positiveInteger("SSV_MAX_REWARDS_PER_24H", 4),
  retentionMs: positiveInteger("SSV_RETENTION_DAYS", 30) * 24 * 60 * 60 * 1000
});

if (
  !/^ca-app-pub-[0-9]+\/[0-9]+$/.test(policy.adUnitID) ||
  policy.adUnitID === "ca-app-pub-3940256099942544/1712485313"
) {
  throw new Error("ADMOB_REWARDED_AD_UNIT_ID must be a full production ad unit ID.");
}
if (policy.rewardItem.length > 64 || /[\u0000-\u001f\u007f]/.test(policy.rewardItem)) {
  throw new Error("ADMOB_REWARD_ITEM is malformed.");
}
if (policy.maximumRewards > 100 || policy.retentionMs > 365 * 24 * 60 * 60 * 1000) {
  throw new Error("SSV quota or retention exceeds the supported safety bound.");
}

const idHashKeyText = required("SSV_ID_HASH_KEY");
if (!/^[0-9a-fA-F]{64}$/.test(idHashKeyText)) {
  throw new Error("SSV_ID_HASH_KEY must be a 64-character hexadecimal secret.");
}
const idHashKey = Buffer.from(idHashKeyText, "hex");

const store = new SQLiteRewardStore(databasePath);
const service = new AdMobSSVService({
  keyProvider: new AdMobPublicKeyProvider(),
  store,
  policy,
  idHashKey
});

const sendJSON = (response, status, body) => {
  const data = Buffer.from(JSON.stringify(body));
  response.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "content-length": data.length,
    "cache-control": "no-store",
    "x-content-type-options": "nosniff"
  });
  response.end(data);
};

const server = http.createServer(async (request, response) => {
  if (request.method === "GET" && request.url === "/healthz") {
    sendJSON(response, 200, { status: "ok" });
    return;
  }
  if (request.method !== "GET" || !request.url?.startsWith("/admob/ssv?")) {
    sendJSON(response, 404, { status: "not_found" });
    return;
  }

  try {
    const result = await service.process(request.url);
    sendJSON(response, 200, { status: "verified", disposition: result.disposition });
    process.stdout.write(`${JSON.stringify({ event: "ssv_callback", disposition: result.disposition })}\n`);
  } catch (error) {
    const known = error instanceof SSVError;
    const status = known ? error.status : 503;
    const code = known ? error.code : "internal_error";
    sendJSON(response, status, { status: "rejected", code });
    process.stderr.write(`${JSON.stringify({ event: "ssv_rejected", code, retryable: known ? error.retryable : true })}\n`);
  }
});

server.requestTimeout = 10_000;
server.headersTimeout = 10_000;
server.keepAliveTimeout = 5_000;

const port = positiveInteger("PORT", 8787);
if (port > 65_535) {
  throw new Error("PORT must be at most 65535.");
}
const host = process.env.HOST?.trim() || "127.0.0.1";
server.listen(port, host, () => {
  process.stdout.write(`${JSON.stringify({ event: "server_started", host, port })}\n`);
});

const shutdown = () => {
  server.close(() => {
    store.close();
    process.exit(0);
  });
};
process.once("SIGTERM", shutdown);
process.once("SIGINT", shutdown);
