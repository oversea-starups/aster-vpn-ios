# SPEC-0013 — 用户路径与流程图（Vibe）

## 主路径（首次安装）
Home → Connect → Demo(60s) → Paywall → Purchase → Connected(Pro)

## 复访路径（未订阅）
Home → Connect → Paywall → Purchase → Connected(Pro)

## 复访路径（已订阅）
Home → Connect → Connected(Pro)

## 失败路径
Home → Connect → Fail → Retry / Switch Location → Connect

## 位置选择路径
Home → Locations → Select → Home → Connect

## 简化流程图（ASCII）
[Home]
  | Connect
  v
[Demo 60s] --timeout--> [Paywall]
  | Purchase                | Restore
  v                         v
[Connected Pro]         [Connected Pro]

[Home] --Fail--> [Retry / Switch Location]
