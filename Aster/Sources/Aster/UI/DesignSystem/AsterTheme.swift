import SwiftUI

enum AsterTheme {
    // Keep one dark foundation and two reserved accents: cyan for secondary
    // navigation, mint for the primary action/protection state, and amber for
    // warnings. The slightly calmer saturation keeps the switch and Pro CTA
    // prominent without making every surface compete for attention.
    static let navy = Color(red: 0.025, green: 0.055, blue: 0.12)
    static let deepBlue = Color(red: 0.055, green: 0.145, blue: 0.255)
    static let cyan = Color(red: 0.24, green: 0.76, blue: 0.90)
    static let mint = Color(red: 0.34, green: 0.90, blue: 0.70)
    static let warning = Color(red: 1.0, green: 0.68, blue: 0.24)

    static let background = LinearGradient(
        colors: [navy, deepBlue, navy],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct AsterCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(AsterTheme.deepBlue, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
    }
}

extension View {
    func asterCard() -> some View {
        modifier(AsterCardModifier())
    }
}
