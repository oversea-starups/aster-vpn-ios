# SPEC-0002 — 页面与信息架构（iOS, US）

## 页面清单（MVP）
1. Home Tab（连接页）
2. Locations Tab（地区选择）
3. Account Tab（订阅、恢复购买、隐私与条款）
4. Paywall（订阅 sheet）
5. First-use Data Disclosure（首次使用 sheet）

## 页面职责

### 1) Home Tab
- 主按钮：圆形 Connect / Disconnect 开关
- 状态：Connecting / Connected / Disconnected
- 信息：当前地区、连接状态
- 转化顺序：状态与连接价值 → Aster Pro 主 CTA

### 2) Locations Tab
- 列表只显示地区名，过滤套餐流量/到期等状态记录
- 连接中不可更换地区；断开后选择即保存并回到 Home

### 3) Account Tab
- Pro 状态与 StoreKit verified expiration date（本地化 `Access through <date>`）
- 升级、恢复购买、管理订阅
- Privacy Policy、Terms of Use

### 4–6) Sheets
- Paywall 只显示 StoreKit 返回的真实方案、价格、试用资格与自动续费说明
- 首次数据说明以 large 不可跳过 sheet 呈现，Continue 后才刷新线路

## 关键 UI 文案（英文）
- Home Title: “Aster”
- Connect CTA: “Connect VPN”
- Connected: “Protected”
- Pro CTA: “Upgrade to Pro”
- Account expiration: “Access through <localized date>”

## 体验原则
- 每个 Tab 只有一个核心任务；Home 只保留“连接并看到保护状态”的主路径
- 固定版式优先，Home/Account 仅在小屏或辅助功能字号回退到隐藏指示器的滚动容器；Locations 因数据长度保留列表滚动
- 会员是主要转化路径；不以第三方广告打断连接或收集 VPN 相关数据
- 优先使用系统控件、≥44pt 触控区域和清晰的状态反馈
