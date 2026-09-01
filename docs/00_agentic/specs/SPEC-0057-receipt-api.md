# SPEC-0057 — 订阅验证 API 规格

## Endpoint
POST /verify-receipt

## Request
{
  "receipt": "<base64>",
  "device_id": "<hash>",
  "app_version": "1.0.0"
}

## Response
{
  "is_pro": true,
  "expires_at": "2026-01-13T00:00:00Z",
  "token": "<jwt>"
}

## 错误
- 400: invalid_receipt
- 403: expired
- 500: server_error
