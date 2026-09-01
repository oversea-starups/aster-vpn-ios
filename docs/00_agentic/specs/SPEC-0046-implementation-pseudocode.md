# SPEC-0046 — 关键逻辑伪代码

## Demo 逻辑
if first_launch && demo_enabled:
  start_demo_timer(60s)
  connect()
  on_demo_end:
    disconnect()
    show_paywall(source="connect_demo_end")

## Paywall 触发
if select_pro_location:
  show_paywall(source="location_lock")

if tap_connect and not_pro and demo_done:
  show_paywall(source="hard_gate")

## 连接失败
if connect_timeout > 8s:
  show_error("Connection Failed")
  suggest_retry_or_switch()
