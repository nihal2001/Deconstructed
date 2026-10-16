import SwiftUI
import UIKit

/// Palette and type for the app. Every colour is one of the five in `Color-scheme.png`,
/// used at its exact value, or a transparency of one of them:
///
///     Jet Black 143642 · Blush Rose D65780 · Alabaster Grey EAE6E5 · Olive 91972A · Seagrass 519E8A
///
/// The app has one look. Screens are solid jet with alabaster text; cards and sheets are
/// alabaster with jet text. Colours that differ between those two contexts are selected by
/// the SwiftUI colour scheme: "dark" means "on jet", "light" means "on alabaster".
enum Theme {
    static let jetHex: UInt32 = 0x143642
    static let roseHex: UInt32 = 0xD65780
    static let alabasterHex: UInt32 = 0xEAE6E5
    static let oliveHex: UInt32 = 0x91972A
    static let seagrassHex: UInt32 = 0x519E8A

    static let jet = Color(light: jetHex, dark: jetHex)
    static let alabaster = Color(light: alabasterHex, dark: alabasterHex)

    // Surfaces
    static let canvas = Color(light: alabasterHex, dark: jetHex)
    static let surface = Color(light: UIColor(hex: alabasterHex), dark: UIColor(hex: alabasterHex).withAlphaComponent(0.10))
    static let fill = Color(light: UIColor(hex: jetHex).withAlphaComponent(0.08), dark: UIColor(hex: alabasterHex).withAlphaComponent(0.14))
    static let hairline = Color(light: UIColor(hex: jetHex).withAlphaComponent(0.16), dark: UIColor(hex: alabasterHex).withAlphaComponent(0.20))

    // Text
    static let ink = Color(light: jetHex, dark: alabasterHex)
    static let inkSoft = Color(light: UIColor(hex: jetHex).withAlphaComponent(0.72), dark: UIColor(hex: alabasterHex).withAlphaComponent(0.78))

    // Accents, exact
    static let rose = Color(light: roseHex, dark: roseHex)
    static let blush = rose
    static let olive = Color(light: oliveHex, dark: oliveHex)
    static let seagrass = Color(light: seagrassHex, dark: seagrassHex)
    /// Warnings and "needs attention" use the rose; there is no separate warning colour.
    static let warning = rose

    /// One colour per criterion, by position, so a criterion keeps its colour everywhere its
    /// score appears. The first four are the palette itself; further criteria reuse it at
    /// reduced strength. Colour is never the only cue: names and numbers sit beside it.
    static let criterionColors: [Color] = {
        let fourth = Color(light: jetHex, dark: alabasterHex) // jet would vanish on a jet panel
        let base = [rose, seagrass, olive, fourth]
        return base + base.map { $0.opacity(0.6) } + [rose.opacity(0.35), seagrass.opacity(0.35)]
    }()

    // Solid fills. (Typed as gradients so they fit anywhere a shape style is expected;
    // both stops are the same colour.)
    static let heroGradient = solid(jetHex)
    static let roseGradient = solid(roseHex)
    static let seagrassGradient = solid(seagrassHex)
    static let oliveGradient = solid(oliveHex)

    private static func solid(_ hex: UInt32) -> LinearGradient {
        LinearGradient(colors: [Color(light: hex, dark: hex)], startPoint: .top, endPoint: .bottom)
    }

    /// Rose → olive → seagrass, for thin accents.
    static let spectrum = LinearGradient(colors: [rose, olive, seagrass], startPoint: .leading, endPoint: .trailing)

    static func criterionColor(_ index: Int) -> Color {
        criterionColors[index % criterionColors.count]
    }

    static let cornerRadius: CGFloat = 18
    static let spacing: CGFloat = 16
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Font {
    /// Optima for names, headings and scores: a flared, calligraphic sans that reads as
    /// considered rather than decorative. Scales with Dynamic Type.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .custom(Typeface.name(for: weight), size: Typeface.size(for: style), relativeTo: style)
    }

    static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom(Typeface.name(for: weight), fixedSize: size)
    }
}

enum Typeface {
    static func name(for weight: Font.Weight) -> String {
        weight == .regular || weight == .light ? "Optima-Regular" : "Optima-Bold"
    }

    static func size(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 36
        case .title: 30
        case .title2: 24
        case .title3: 21
        case .headline: 18
        case .subheadline: 16
        default: 17
        }
    }
}

// MARK: - Surfaces and buttons

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.spacing

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline.opacity(0.5), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 10, y: 5)
            .environment(\.colorScheme, .light)
    }
}

/// A solid seagrass panel for the most important thing on a screen, with light text.
struct HeroModifier: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.seagrassGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func card(padding: CGFloat = Theme.spacing) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Standard screen background and list styling.
    /// The solid screen colour: jet on main screens, alabaster inside sheets.
    func screenBackground() -> some View {
        background(Theme.canvas.ignoresSafeArea())
    }

    /// Sheets and other modals use the light alabaster surface.
    func modalSurface() -> some View {
        preferredColorScheme(.light)
    }

    func hero(padding: CGFloat = 20) -> some View {
        modifier(HeroModifier(padding: padding))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.alabaster)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .background(isEnabled ? AnyShapeStyle(Theme.roseGradient) : AnyShapeStyle(Theme.inkSoft.opacity(0.45)),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(isEnabled ? 0.18 : 0), radius: 6, y: 3)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? tint : Theme.inkSoft.opacity(0.6))
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
