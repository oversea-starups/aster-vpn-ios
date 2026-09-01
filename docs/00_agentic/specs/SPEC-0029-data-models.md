# SPEC-0029 — 数据模型（规划级）

## Location
- id: String
- name: String ("United States")
- city: String ("New York")
- region: String ("US")
- isPro: Bool
- isRecommended: Bool
- latencyMs: Int? (optional)
- isAvailable: Bool

## SubscriptionProduct
- id: String
- displayName: String
- price: String
- period: String ("/mo", "/yr")
- isTrial: Bool

## ConnectionState
- status: disconnected | connecting | connected | failed
- locationId: String?
- protocol: String
- errorCode: String?
- connectedAt: Date?
