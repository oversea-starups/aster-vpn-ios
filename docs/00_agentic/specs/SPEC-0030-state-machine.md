# SPEC-0030 — 连接状态机

## 状态
- disconnected
- connecting
- connected
- failed

## 事件
- user_connect
- user_disconnect
- connect_success
- connect_fail
- timeout

## 转移
- disconnected + user_connect → connecting
- connecting + connect_success → connected
- connecting + connect_fail → failed
- connecting + timeout → failed
- failed + user_connect → connecting
- connected + user_disconnect → disconnected
