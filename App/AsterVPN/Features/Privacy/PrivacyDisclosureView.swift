import SwiftUI

struct PrivacyDisclosureView: View {
    let requiresAcknowledgement: Bool
    let continueAction: () -> Void

    init(
        requiresAcknowledgement: Bool = true,
        continueAction: @escaping () -> Void = {}
    ) {
        self.requiresAcknowledgement = requiresAcknowledgement
        self.continueAction = continueAction
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.indigo)
                        .accessibilityHidden(true)

                    Text("使用前的数据说明")
                        .font(.largeTitle.bold())
                    Text("Aster VPN 会处理提供账号、订阅和 VPN 服务所必需的数据。请在登录、购买或建立连接前阅读以下说明。")
                        .foregroundStyle(.secondary)
                }

                disclosureCard(
                    title: "账号与支持",
                    systemImage: "person.crop.circle",
                    detail: "注册时会处理邮箱、可选用户名和经安全散列后的密码。邮箱用于登录、验证码和必要的服务通知；配置的邮件服务商可能参与邮件投递。"
                )

                disclosureCard(
                    title: "订阅与交易",
                    systemImage: "creditcard",
                    detail: "App 内订阅由 Apple 处理。服务端保存商品、交易标识、订阅状态和到期时间来核验并开通权益；Aster VPN 不接收你的银行卡资料。"
                )

                disclosureCard(
                    title: "VPN 服务用量",
                    systemImage: "arrow.up.arrow.down.circle",
                    detail: "为执行套餐额度，服务端按账号记录聚合的上传/下载字节数和时间。API 与 VPN 节点在建立连接时会接触网络地址；当前 App 不包含广告或第三方分析 SDK。"
                )

                disclosureCard(
                    title: "流量内容与运营日志",
                    systemImage: "eye.slash",
                    detail: "当前客户端不会把浏览内容、完整访问网址或 DNS 查询上传到账号 API，也不包含广告或第三方分析 SDK。VPN 节点会为转发流量处理数据包；API、节点和基础设施可能处理网络地址、连接时间、字节数及安全/错误信息。具体字段、处理方和保留期以完整隐私政策为准。Aster VPN 不会出售 VPN 流量数据或将其用于广告画像。"
                )

                VStack(spacing: 12) {
                    Link(
                        "查看完整隐私政策",
                        destination: AppConfiguration.current.privacyPolicyURL
                    )
                    Link(
                        "查看服务条款",
                        destination: AppConfiguration.current.termsOfServiceURL
                    )
                }
                .frame(maxWidth: .infinity)

                if requiresAcknowledgement {
                    Button {
                        continueAction()
                    } label: {
                        Text("我已阅读，继续")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(requiresAcknowledgement ? "" : "数据与隐私")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func disclosureCard(
        title: String,
        systemImage: String,
        detail: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.indigo)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }
}
