# Aster VPN Roadmap

> Last reviewed: 2026-08-31  
> 路线图表达阶段结果；具体任务、依赖和 DoD 以 [TODO.md](TODO.md) 为准。

## Phase 1 — Buildable Foundation (Build-verified)

- [x] XcodeGen project、App target、PacketTunnel target。
- [x] SwiftUI 连接入口与基础系统状态展示。
- [x] App Group 配置文件与 Libbox 接线。
- [x] unsigned iOS Simulator build。

## Phase 2 — Real Connection Core Loop (Current)

**Outcome:** 在真机用一个受控节点证明连接、可用流量、可信状态和断开。

- [x] Versioned schema-v2 node/tunnel contract and parser/test bundles。
- [ ] Network Extension capability/signing verification。
- [ ] Real-node device happy path on Wi-Fi and cellular。
- [ ] Explicit failed/timeout/retry state machine。
- [x] Core automated test baseline for reward policy/ledger and tunnel config。
- [x] Fixed Home/Account layouts, circular connection control, three-tab shell and privacy disclosure sheet。

## Phase 3 — Nodes and Reliability

**Outcome:** 少量可运营节点可选择，失败可恢复。

- [x] Locations UI, HTTPS catalog, last-known-good and selected-node persistence。
- [ ] Revocable production endpoint and 3-node device switching evidence。
- [ ] Node validation, health and fallback policy。
- [ ] Background/network-switch/reasserting verification。
- [ ] Resource measurement and Libbox reproducible build。

## Phase 4 — Access and Subscription Core Loop

**Outcome:** 用户体验连接价值后能购买、恢复并获得 entitlement。

- [x] StoreKit 2 client product, entitlement, purchase and restore state。
- [x] Account entitlement surface with localized expiration-date display。
- [x] Rewarded access policy, balance, UMP and AdMob client integration。
- [x] Local AdMob SSV verifier and client anti-abuse implementation。
- [ ] Resolve Apple VPN Guideline 5.4 vs AdMob; recommended StoreKit-only App Store target。
- [ ] Production external setup only if ads are retained; StoreKit sandbox verification。
- [ ] Paywall purchase/restore/expiry device evidence。
- [ ] Privacy/Terms and minimal funnel events。

## Phase 5 — Release Validation

**Outcome:** TestFlight 和 App Store 上可观测、合规、可恢复。

- [ ] Multi-device QA and accessibility。
- [x] Replace Packet Tunnel private KVC with the generated/exported public Libbox fd resolver and add source/symbol guards。
- [ ] Re-run the previously working real-device route after the fd bridge change。
- [ ] Execute current 50 unit + 9 UI suite on healthy arm64 CI；已有 45 unit 为 44 pass + 1 x86_64 architecture skip，新增 parser/region/cache/recovery cases 与 Account/tab/control UI 修复后 runtime 待重跑。
- [ ] Crash/connection diagnostics without sensitive data。
- [ ] App Store metadata, review notes and legal URLs。
- [ ] TestFlight evidence and release checklist。
