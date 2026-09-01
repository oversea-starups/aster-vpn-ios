# Aster VPN Agentic Coding Guide

> Version: 1.0  
> Updated: 2026-07-17  
> Purpose: 让 AI agent 或开发者在没有旧对话的情况下，安全地完成可验证的小步交付。

## 1. 执行北极星

所有工作围绕一个纵向闭环：

```text
用户意图 -> 开始连接 -> 真实流量可用 -> 状态可信 -> 失败可恢复 -> 订阅理由明确
```

如果任务不能直接提升上述闭环，默认不进入当前迭代。

## 2. 证据优先级

1. 用户明确的最终决定。
2. 当前代码、配置、测试、构建和真机运行证据。
3. Product Brief、Status、ADR、Architecture、TODO 等当前 SSOT。
4. 编号 SPEC。
5. 旧说明、注释和建议。

发现冲突时不要猜：保留更高优先级事实，把未决问题写入 `PROJECT_STATUS.md`。

## 3. 状态等级

| Level | 含义 | 最低证据 |
| --- | --- | --- |
| Planned | 已确定要做，尚无代码 | TODO + acceptance criteria |
| Implemented | 代码存在 | source inspection |
| Build-verified | 当前工程可编译/测试 | command + result |
| Device-verified | 目标真机和网络场景通过 | device test record |
| Release-verified | TestFlight/App Store 配置与生产监控通过 | release evidence |

禁止用“完成”替代这些精确状态。VPN 核心能力至少达到 device-verified 才能称为可用。

## 4. 每个任务的标准循环

### 4.1 Orient

- 读 `PRODUCT_BRIEF.md`、`PROJECT_STATUS.md`、`TODO.md`、相关 ADR/SPEC。
- 检查工作区和已有修改，不覆盖用户工作。
- 用代码搜索确认入口、调用链、测试和配置来源。

### 4.2 Frame

在动手前写清：

- 用户结果与非目标。
- 当前证据与关键假设。
- 最小变更面。
- 可执行验收标准。
- 风险，尤其是签名、隐私、凭据和真机依赖。

### 4.3 Implement a vertical slice

- 一次任务只改变一个行为闭环。
- 先定义契约和状态，再接 UI。
- 为外部/系统边界设计失败路径；不得静默失败。
- Extension 不引入非必要依赖，不记录流量或秘密。
- 相关代码引用 SPEC/ADR 时只解释“为什么”，避免重复需求正文。

### 4.4 Verify proportionally

按风险从快到慢执行：

1. 静态检查与 unit tests。
   - 完整 arm64 CI 门禁使用 `ASTER_TEST_DESTINATION_ID=<udid> ./scripts/run_quality_gate.sh`；必须保存脚本生成的 `.xcresult`、summary 与日志，且当前 59/59、0 failure、0 skip。
2. unsigned simulator build。
3. StoreKit configuration/sandbox test（订阅任务）。
4. 签名真机构建与 Network Extension 验收（VPN 任务必需）。
5. TestFlight/release 验收（发布任务）。
   - 对最终签名产物执行 `./scripts/validate_signed_archive.sh /absolute/path/to/Aster.xcarchive`，不得只检查源码或未签名 simulator bundle。

验证失败时记录真实失败，不把环境阻塞写成代码通过或失败。

### 4.5 Document and hand off

同一变更中更新：

- `PROJECT_STATUS.md`：只放真实进度、风险、阻塞、下一步。
- `docs/TODO.md`：删除已验证完成项，补后续依赖和 DoD。
- `docs/ARCHITECTURE.md`：实现结构或边界改变时更新。
- `docs/DECISIONS.md`：出现长期有效且已确认的取舍时更新。
- 相关 SPEC：需求本身被用户确认修改时更新。

交接格式：

```markdown
Outcome:
Changed:
Verified:
Not verified:
Risks / open questions:
Next action:
```

## 5. Definition of Done

一个切片只有同时满足以下条件才完成：

- 行为和非目标与 Core Job 一致。
- success、failure、timeout/cancel 路径已定义。
- 关键纯逻辑有自动化测试；构建命令通过。
- VPN/entitlement/真实流量相关功能有真机证据。
- 不记录流量、节点凭据、token、receipt 或个人数据。
- 文档状态与实现一致，没有把 planned 模块画成 current。
- 交接包含具体文件、命令、结果和未验证项。

## 6. VPN 专项检查

- App Group、provider bundle ID、entitlements 和 Developer Portal 完全一致。
- 输入配置经过 schema/version/范围校验；写入原子化；错误可诊断。
- UI 状态不依赖显示字符串；系统状态与流量可用性分开。
- 覆盖权限拒绝、节点不可达、DNS 失败、超时、网络切换、前后台、重连和用户断开。
- 在目标设备上记录 Extension 内存/CPU，不依赖固定预算传言。
- 日志只包含生命周期、非敏感错误码和相关 ID；所有凭据脱敏。

## 7. 建议的首批可执行切片

1. `VPNNode` + versioned tunnel DTO + parser tests。
2. 单节点真机 happy path + 验证记录模板。
3. 显式连接状态机 + failure/timeout tests。
4. Locations 选择驱动真实配置。
5. StoreKit 2 entitlement + demo/paywall。

每个切片的依赖和验收标准以 `docs/TODO.md` 为准。
