# SPEC-0008 — 事件埋点字段与口径

## 核心事件
1) app_open
- props: app_version, build, first_open(bool)

2) connect_tap
- props: source (home|paywall), location, is_pro

3) connect_success
- props: latency_ms, location, protocol, is_demo(bool)

4) connect_fail
- props: error_code, location, protocol, is_demo(bool)

5) demo_start
- props: location

6) demo_end
- props: reason(timeout|user_disconnect|error)

7) paywall_view
- props: source (open|connect_demo_end|location_lock|hard_gate)

8) purchase_start
- props: product_id

9) purchase_success
- props: product_id, price, currency

10) restore_success
- props: restored_count

11) session_length
- props: seconds

## 口径说明
- connect_success 仅计入建立隧道成功且完成握手。
- demo_end: timeout 指累计 10 分钟 Protected 使用时长耗尽后自动结束；断开期间不计时。
- paywall_view 仅在实际展示时记录。
