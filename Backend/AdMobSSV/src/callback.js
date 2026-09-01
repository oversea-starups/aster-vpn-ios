import { createHash, createPublicKey, verify } from "node:crypto";

const SIGNATURE_SUFFIX = /&signature=([^&]+)&key_id=([^&]+)$/;
const INVALID_PERCENT_ESCAPE = /%(?![0-9a-fA-F]{2})/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const TRANSACTION_PATTERN = /^[0-9a-f]{16,128}$/i;
const DECIMAL_PATTERN = /^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,6})?$/;

export class SSVError extends Error {
  constructor(code, message, { status = 400, retryable = false } = {}) {
    super(message);
    this.name = "SSVError";
    this.code = code;
    this.status = status;
    this.retryable = retryable;
  }
}

export function extractSignedCallback(rawURL) {
  if (typeof rawURL !== "string" || rawURL.length === 0 || rawURL.length > 4096) {
    throw new SSVError("invalid_url", "Callback URL is missing or too long.");
  }

  const questionMark = rawURL.indexOf("?");
  if (questionMark < 0 || questionMark === rawURL.length - 1 || rawURL.includes("#")) {
    throw new SSVError("invalid_query", "Callback query is missing or malformed.");
  }

  const rawQuery = rawURL.slice(questionMark + 1);
  const match = rawQuery.match(SIGNATURE_SUFFIX);
  if (!match || match.index === undefined || match.index === 0) {
    throw new SSVError(
      "invalid_signature_position",
      "signature and key_id must be the final query parameters in that order."
    );
  }

  const signedContent = rawQuery.slice(0, match.index);
  if (INVALID_PERCENT_ESCAPE.test(rawQuery)) {
    throw new SSVError("invalid_percent_encoding", "Callback contains invalid percent encoding.");
  }

  const signedNames = new URLSearchParams(signedContent);
  if (signedNames.has("signature") || signedNames.has("key_id")) {
    throw new SSVError("duplicate_security_parameter", "Security parameters must occur once.");
  }

  let encodedSignature;
  let keyID;
  try {
    encodedSignature = decodeURIComponent(match[1]);
    keyID = decodeURIComponent(match[2]);
  } catch {
    throw new SSVError("invalid_security_encoding", "Security parameters are malformed.");
  }

  if (!/^[A-Za-z0-9_-]+={0,2}$/.test(encodedSignature)) {
    throw new SSVError("invalid_signature_encoding", "Signature is not valid base64url.");
  }
  if (!/^[0-9]{1,20}$/.test(keyID)) {
    throw new SSVError("invalid_key_id", "key_id is malformed.");
  }

  const signature = Buffer.from(encodedSignature, "base64url");
  if (signature.length < 64 || signature.length > 80) {
    throw new SSVError("invalid_signature_length", "Signature length is invalid.");
  }

  return {
    rawQuery,
    signedContent,
    signature,
    keyID
  };
}

export function verifySignedCallback(envelope, publicKeyPEM) {
  let publicKey;
  try {
    publicKey = createPublicKey(publicKeyPEM);
  } catch {
    throw new SSVError(
      "invalid_verification_key",
      "The AdMob verification key is invalid.",
      { status: 503, retryable: true }
    );
  }
  if (publicKey.asymmetricKeyType !== "ec") {
    throw new SSVError(
      "invalid_verification_key",
      "The AdMob verification key is not an EC key.",
      { status: 503, retryable: true }
    );
  }

  const isValid = verify(
    "sha256",
    Buffer.from(envelope.signedContent, "utf8"),
    publicKey,
    envelope.signature
  );
  if (!isValid) {
    throw new SSVError("signature_mismatch", "Callback signature is invalid.", { status: 403 });
  }
}

export function parseVerifiedPayload(signedContent) {
  const params = new URLSearchParams(signedContent);
  const value = (name) => {
    const values = params.getAll(name);
    if (values.length !== 1 || values[0].length === 0) {
      throw new SSVError("invalid_parameter", `${name} must occur exactly once.`);
    }
    return values[0];
  };

  const adNetwork = value("ad_network");
  const adUnit = value("ad_unit");
  const rewardAmount = value("reward_amount");
  const rewardItem = value("reward_item");
  const timestampText = value("timestamp");
  const transactionID = value("transaction_id").toLowerCase();
  const userID = value("user_id").toLowerCase();
  const attemptID = value("custom_data").toLowerCase();

  if (!/^[0-9]{1,20}$/.test(adNetwork)) {
    throw new SSVError("invalid_ad_network", "ad_network is malformed.");
  }
  if (!/^[0-9]{1,32}$/.test(adUnit)) {
    throw new SSVError("invalid_ad_unit", "ad_unit is malformed.");
  }
  if (!DECIMAL_PATTERN.test(rewardAmount)) {
    throw new SSVError("invalid_reward_amount", "reward_amount is malformed.");
  }
  if (rewardItem.length > 64 || /[\u0000-\u001f\u007f]/.test(rewardItem)) {
    throw new SSVError("invalid_reward_item", "reward_item is malformed.");
  }
  if (!/^[0-9]{12,16}$/.test(timestampText)) {
    throw new SSVError("invalid_timestamp", "timestamp is malformed.");
  }
  if (!TRANSACTION_PATTERN.test(transactionID)) {
    throw new SSVError("invalid_transaction_id", "transaction_id is malformed.");
  }
  if (!UUID_PATTERN.test(userID) || !UUID_PATTERN.test(attemptID)) {
    throw new SSVError("invalid_identity", "user_id or custom_data is malformed.");
  }

  const rewardedAtMs = Number(timestampText);
  if (!Number.isSafeInteger(rewardedAtMs)) {
    throw new SSVError("invalid_timestamp", "timestamp exceeds the safe integer range.");
  }

  return {
    adNetwork,
    adUnit,
    rewardAmount: normalizeDecimal(rewardAmount),
    rewardItem,
    rewardedAtMs,
    transactionID,
    userID,
    attemptID
  };
}

export function validatePayload(payload, policy, nowMs) {
  const expectedAdUnit = policy.adUnitID.includes("/")
    ? policy.adUnitID.slice(policy.adUnitID.lastIndexOf("/") + 1)
    : policy.adUnitID;

  if (payload.adUnit !== expectedAdUnit) {
    throw new SSVError("unexpected_ad_unit", "Callback ad unit does not match this service.", {
      status: 403
    });
  }
  if (
    payload.rewardAmount !== normalizeDecimal(policy.rewardAmount) ||
    payload.rewardItem !== policy.rewardItem
  ) {
    throw new SSVError("unexpected_reward", "Callback reward does not match this service.", {
      status: 403
    });
  }

  const ageMs = nowMs - payload.rewardedAtMs;
  if (ageMs > policy.maximumCallbackAgeMs) {
    throw new SSVError("stale_callback", "Callback is older than the accepted window.", {
      status: 403
    });
  }
  if (ageMs < -policy.maximumFutureSkewMs) {
    throw new SSVError("future_callback", "Callback timestamp is too far in the future.", {
      status: 403
    });
  }
}

export function rawQueryHash(rawQuery) {
  return createHash("sha256").update(rawQuery, "utf8").digest("hex");
}

export function normalizeDecimal(value) {
  if (!DECIMAL_PATTERN.test(String(value))) {
    throw new SSVError("invalid_decimal", "Configured reward amount is malformed.");
  }
  return String(value).replace(/\.0+$/, "").replace(/(\.[0-9]*?)0+$/, "$1");
}
