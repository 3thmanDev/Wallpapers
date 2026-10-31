import SwiftUI

enum Theme {
    static let background = Color(red: 0.047, green: 0.047, blue: 0.063)
    static let surface = Color(red: 0.094, green: 0.094, blue: 0.122)
    static let raised = Color(red: 0.137, green: 0.137, blue: 0.173)
    static let line = Color(red: 0.188, green: 0.188, blue: 0.231)
    static let ink = Color(red: 0.949, green: 0.949, blue: 0.961)
    static let secondary = Color(red: 0.612, green: 0.612, blue: 0.671)

    /// Soft violet; text on it is dark, not white, so it stays readable.
    static let accent = Color(red: 0.635, green: 0.565, blue: 1.0)
    static let accentInk = Color(red: 0.071, green: 0.055, blue: 0.157)
    static let accentSoft = Color(red: 0.635, green: 0.565, blue: 1.0).opacity(0.16)
    static let warn = Color(red: 0.961, green: 0.725, blue: 0.282)
    static let bad = Color(red: 1.0, green: 0.42, blue: 0.42)
}

enum CairoWeight: String {
    case regular = "Cairo-Regular"
    case medium = "Cairo-Medium"
    case semibold = "Cairo-SemiBold"
    case bold = "Cairo-Bold"
    case extraBold = "Cairo-ExtraBold"
    case black = "Cairo-Black"
}

extension Font {
    static func cairo(_ size: CGFloat, _ weight: CairoWeight = .regular) -> Font {
        .custom(weight.rawValue, size: size)
    }
}

extension View {
    /// Arabic right-to-left layout, Cairo font and the dark look, applied to the root and every sheet.
    func appEnvironment() -> some View {
        font(.cairo(17))
            .foregroundColor(Theme.ink)
            .tint(Theme.accent)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, AppLocale.locale)
            .preferredColorScheme(.dark)
    }
}

enum AppLocale {
    static let locale = Locale(identifier: "ar@numbers=latn")
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                }
                Text(title).font(.cairo(17, .bold))
            }
            .foregroundColor(Theme.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accent))
        }
        .buttonStyle(PressableStyle())
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                }
                Text(title).font(.cairo(17, .semibold))
            }
            .foregroundColor(Theme.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.raised))
        }
        .buttonStyle(PressableStyle())
    }
}

/// A short message that floats at the bottom and fades away by itself.
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.cairo(15, .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Theme.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Theme.raised).shadow(color: .black.opacity(0.35), radius: 16, y: 6))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 3_200_000_000)
                        withAnimation(.easeOut(duration: 0.25)) { self.message = nil }
                    }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}
