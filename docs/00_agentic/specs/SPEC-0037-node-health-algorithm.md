# SPEC-0037 — 节点健康检查（伪代码）

## 目的
自动下线不可用节点，避免连接失败。

## 伪代码
1. 每 6 小时对全部节点发起轻量握手测试
2. 记录响应时间与失败次数
3. 失败率 > 20% → 标记为不可用
4. 连续 24 小时恢复 → 重新上线

## 数据字段
- lastCheckAt
- failCount
- successCount
- avgLatencyMs
- isAvailable
