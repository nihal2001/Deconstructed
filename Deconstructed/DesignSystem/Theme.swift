import SwiftUI
import UIKit

/// Palette and type for the app. Every colour the app sets is one of the five in
/// `Color-scheme.png`, used at its exact value, or a transparency of one of them:
///
///     Jet Black 143642 · Blush Rose D65780 · Alabaster Grey EAE6E5 · Olive 91972A · Seagrass 519E8A
///
/// The app has one look, in the two layers Liquid Glass asks for. Content sits on a jet canvas
/// lit by soft pools of the accent colours, in frosted panels with alabaster text. Controls float
/// above it on Liquid Glass, which takes its colour from whatever is behind it.
enum Theme {
    static let jetHex: UInt32 = 0x143642
    static let roseHex: UInt32 = 0xD65780
    static let alabasterHex: UInt32 = 0xEAE6E5
    static let oliveHex: UInt32 = 0x91972A
    static let seagrassHex: UInt32 = 0x519E8A

    static let jet = Color(hex: jetHex)
    static let alabaster = Color(hex: alabasterHex)

    // Surfaces
    static let canvas = jet
    static let fill = alabaster.opacity(0.14)
    static let hairline = alabaster.opacity(0.20)
    /// The light catching a panel's edge: strongest at the top left, as if lit from above.
    static let rim = LinearGradient(colors: [alabaster.opacity(0.42), alabaster.opacity(0.06), alabaster.opacity(0.16)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)

    // Text
    static let ink = alabaster
    static let inkSoft = alabaster.opacity(0.78)

    // Accents, exact
    static let rose = Color(hex: roseHex)
    static let blush = rose
    static let olive = Color(hex: oliveHex)
    static let seagrass = Color(hex: seagrassHex)
    /// Warnings and "needs attention" use the rose; there is no separate warning colour.
    static let warning = rose

    /// One colour per criterion, by position, so a criterion keeps its colour everywhere its
    /// score appears. The first four are the palette itself; further criteria reuse it at
    /// reduced strength. Colour is never the only cue: names and numbers sit beside it.
    static let criterionColors: [Color] = {
        let base = [rose, seagrass, olive, alabaster] // alabaster, because jet would vanish on the canvas
        return base + base.map { $0.opacity(0.6) } + [rose.opacity(0.35), seagrass.opacity(0.35)]
    }()

    // Solid fills. (Typed as gradients so they fit anywhere a shape style is expected;
    // both stops are the same colour.)
    static let roseGradient = solid(rose)
    static let seagrassGradient = solid(seagrass)
    static let oliveGradient = solid(olive)
    /// For things that rank below the accent colours and must still show up on the canvas.
    static let mutedGradient = solid(alabaster.opacity(0.24))

    private static func solid(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color], startPoint: .top, endPoint: .bottom)
    }

    /// Rose → olive → seagrass, for thin accents.
    static let spectrum = LinearGradient(colors: [rose, olive, seagrass], startPoint: .leading, endPoint: .trailing)

    static func criterionColor(_ index: Int) -> Color {
        criterionColors[index % criterionColors.count]
    }

    static let cornerRadius: CGFloat = 24
    static let spacing: CGFloat = 16
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
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

/// Everything behind the content: the jet canvas, lit by pools of the accent colours so the
/// frosted panels and the glass above them have something to pick up.
struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Theme.canvas
            pool(Theme.seagrass, strength: 0.60, at: UnitPoint(x: 1, y: 0), reach: 460)
            pool(Theme.rose, strength: 0.42, at: UnitPoint(x: 0, y: 0.52), reach: 400)
            pool(Theme.olive, strength: 0.40, at: UnitPoint(x: 0.9, y: 1), reach: 440)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func pool(_ color: Color, strength: Double, at center: UnitPoint, reach: CGFloat) -> some View {
        RadialGradient(colors: [color.opacity(strength), color.opacity(0)], center: center, startRadius: 0, endRadius: reach)
    }
}

extension View {
    /// Liquid Glass, for the layer of controls that floats above the content. `tint` colours it
    /// and `interactive` makes it respond to touch. Before iOS 26 it falls back to a material,
    /// or to the tint alone when that is opaque.
    ///
    /// Untinted glass is tinted jet: glass turns light over something bright like the map, and
    /// the app's text is always alabaster.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(Glass.regular.tint(tint ?? Theme.jet.opacity(0.55)).interactive(interactive), in: shape)
        } else {
            background(tint ?? .clear, in: shape)
                .background(.regularMaterial, in: shape)
                .overlay { shape.strokeBorder(Theme.rim, lineWidth: 1) }
        }
    }

    /// Frosted glass for the content layer. Liquid Glass belongs to controls, so panels of
    /// content use this: a material, with the same lit edge.
    func frosted<S: InsettableShape>(_ shape: S, tint: Color = Theme.alabaster.opacity(0.05)) -> some View {
        background(tint, in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay { shape.strokeBorder(Theme.rim, lineWidth: 1) }
            .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
    }
}

/// Lets neighbouring glass share one sampling region and flow into each other as they change.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 4
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.spacing

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frosted(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// A seagrass-tinted panel for the most important thing on a screen.
struct HeroModifier: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frosted(RoundedRectangle(cornerRadius: 30, style: .continuous), tint: Theme.seagrass.opacity(0.42))
    }
}

extension View {
    func card(padding: CGFloat = Theme.spacing) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Standard screen background and list styling.
    func screenBackground() -> some View {
        background(AmbientBackground())
    }

    /// For sheets that stop short of full height. iOS 26 makes those glass as long as nothing
    /// opaque covers them; earlier versions get the same background as a screen.
    @ViewBuilder
    func partialSheetBackground() -> some View {
        if #available(iOS 26, *) {
            scrollContentBackground(.hidden)
        } else {
            scrollContentBackground(.hidden).screenBackground()
        }
    }

    func hero(padding: CGFloat = 20) -> some View {
        modifier(HeroModifier(padding: padding))
    }

    /// A bar pinned under a scrolling screen. On iOS 26 it floats, and the content fades out
    /// beneath it instead of stopping at an edge.
    @ViewBuilder
    func floatingFooter<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        let bar = bar()
        if #available(iOS 26, *) {
            safeAreaBar(edge: .bottom, spacing: 0) { bar }
        } else {
            safeAreaInset(edge: .bottom, spacing: 0) { bar.background(.regularMaterial) }
        }
    }

    /// Text input sunk into a panel, in place of the system's rounded border.
    func inputField() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1)
            }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Theme.alabaster : Theme.inkSoft)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .contentShape(Capsule())
            .liquidGlass(Capsule(), tint: isEnabled ? Theme.rose : nil, interactive: isEnabled)
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
            .contentShape(Capsule())
            .liquidGlass(Capsule(), interactive: isEnabled)
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
