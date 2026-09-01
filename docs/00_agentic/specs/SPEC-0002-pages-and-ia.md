# SPEC-0002 — 页面与信息架构（iOS, US）

## 页面清单（MVP）
1. Home Tab（连接页）
2. Locations Tab（地区选择）
3. Account Tab（订阅、免费时长、恢复购买、隐私与条款）
4. Paywall（订阅 sheet）
5. Rewarded Access（广告奖励 sheet）
6. First-use Data Disclosure（首次使用 sheet）

## 页面职责

### 1) Home Tab
- 主按钮：圆形 Connect / Disconnect 开关
- 状态：Connecting / Connected / Disconnected
- 信息：当前地区、连接状态、保护时间
- 转化顺序：状态与连接价值 → Aster Pro 主 CTA → rewarded time 次 CTA

### 2) Locations Tab
- 列表只显示地区名，过滤套餐流量/到期等状态记录
- 连接中不可更换地区；断开后选择即保存并回到 Home

### 3) Account Tab
- Pro 状态与 StoreKit verified expiration date（本地化 `Access through <date>`）
- 免费保护时间、观看 rewarded video、升级、恢复购买、管理订阅
- Privacy choices、Privacy Policy、Terms of Use

### 4–6) Sheets
- Paywall 只显示 StoreKit 返回的真实方案、价格、试用资格与自动续费说明
- Rewarded Access 明确 +10 min、5 分钟冷却、24 小时奖励上限和自愿观看
- 首次数据说明以 medium/large 不可跳过 sheet 呈现，Continue 后才刷新线路或准备广告

## 关键 UI 文案（英文）
- Home Title: “Aster”
- Connect CTA: “Connect VPN”
- Connected: “Protected”
- Pro CTA: “Upgrade to Pro”
- Reward CTA: “Add time · +10 min”
- Account expiration: “Access through <localized date>”

## 体验原则
- 每个 Tab 只有一个核心任务；Home 只保留“连接并看到保护状态”的主路径
- 固定版式优先，Home/Account 仅在小屏或辅助功能字号回退到隐藏指示器的滚动容器；Locations 因数据长度保留列表滚动
- 会员是主要转化路径，广告是明确知情、用户主动选择的留存路径，二者不自动弹出、不打断连接
- 优先使用系统控件、≥44pt 触控区域和清晰的状态反馈
