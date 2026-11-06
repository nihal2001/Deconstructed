import SwiftUI
import UIKit

/// Palette and type for the app: glass gelato, Ocean Neon.
///
/// Content sits on calm steel. Panels are glossy frosted glass: a white gradient with a bright
/// top edge and a soft diffuse shadow, very round. Colour is saved for what matters: the key
/// panel on each screen is a cobalt-to-ocean glass slab, the podium is glossy coral, cyan and
/// cobalt scoops, the primary action is cobalt, and criteria keep their own scoop colours. Text and surfaces are
/// dynamic, so a subtree forced into the dark colour scheme (the key panel) reads in white.
///
/// The app itself is light only.
enum Theme {
    // Steel
    static let steelTopHex: UInt32 = 0xEEF2F6
    static let steelBottomHex: UInt32 = 0xDFE5EC
    static let stockHex: UInt32 = steelTopHex
    static let inkHex: UInt32 = 0x18202B
    static let inkSoftHex: UInt32 = 0x56606C

    // Scoops (Ocean Neon)
    static let coralHex: UInt32 = 0xFF4D3A
    static let cobaltHex: UInt32 = 0x2F6BFF
    static let amberHex: UInt32 = 0xFFB000
    static let aquaHex: UInt32 = 0x00C2A8
    static let violetHex: UInt32 = 0x8B3DFF
    static let pinkHex: UInt32 = 0xFF4FA3

    static let coral = Color(hex: coralHex)
    static let cobalt = Color(hex: cobaltHex)
    static let amber = Color(hex: amberHex)
    static let aqua = Color(hex: aquaHex)
    static let violet = Color(hex: violetHex)
    static let pink = Color(hex: pinkHex)

    // Surfaces
    static let canvas = Color(hex: steelTopHex)
    static let canvasGradient = LinearGradient(colors: [Color(hex: steelTopHex), Color(hex: steelBottomHex)],
                                               startPoint: .top, endPoint: .bottom)
    /// A glass panel's body.
    static let plate = dynamic(light: UIColor.white.withAlphaComponent(0.72), dark: UIColor.white.withAlphaComponent(0.16))
    /// Sunk wells: unselected chips, tracks.
    static let fill = dynamic(light: UIColor(hex: 0xE3E8EF), dark: UIColor.white.withAlphaComponent(0.20))
    /// Quiet dividers.
    static let hairline = dynamic(light: UIColor(hex: 0xD5DCE4), dark: UIColor.white.withAlphaComponent(0.28))
    /// The bright edge round every glass panel and control.
    static let rule = dynamic(light: UIColor.white.withAlphaComponent(0.9), dark: UIColor.white.withAlphaComponent(0.45))
    static let ruleWidth: CGFloat = 1
    /// The colour of a panel's soft shadow.
    static let shadowInk = Color(hex: 0x1E2836)

    // Text
    static let ink = dynamic(light: UIColor(hex: inkHex), dark: .white)
    static let inkSoft = dynamic(light: UIColor(hex: inkSoftHex), dark: UIColor.white.withAlphaComponent(0.92))
    /// Text on a cobalt fill.
    static let onTint = Color.white

    // Roles. Text-safe on glass and steel (4.5:1 or better).
    /// The one interactive colour: links, selection, the tab bar.
    static let tint = Color(hex: 0x1F55E0)
    /// The key panel and primary actions: cobalt to ocean blue. Both ends hold white text at
    /// 4.5:1 or better.
    static let keyGradient = LinearGradient(colors: [Color(hex: 0x2452E0), Color(hex: 0x0B6FB8)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    /// Done, visited, balanced.
    static let positive = Color(hex: 0x0A8061)
    /// Saved / want to try.
    static let saved = Color(hex: 0x2A5FE8)
    /// Problems and anything that needs attention, including the demo marker.
    static let warning = Color(hex: 0xD11F3F)

    /// One colour per criterion, by position, so a criterion keeps its colour everywhere its
    /// score appears. Colour is never the only cue: names and numbers sit beside it.
    static let criterionColors: [Color] = {
        let base = [coral, cobalt, amber, aqua, violet, pink]
        return base + base.map { $0.opacity(0.6) }
    }()

    static func criterionColor(_ index: Int) -> Color {
        criterionColors[index % criterionColors.count]
    }

    /// The glossy fill for a podium place: coral, cyan, cobalt; steel below that.
    static func podium(_ rank: Int) -> LinearGradient {
        let pair: (UInt32, UInt32) = switch rank {
        case 1: (0xFF7A66, 0xF0402C)
        case 2: (0x5FDCFF, 0x00B4F0)
        case 3: (0x5B8CFF, 0x2F6BFF)
        default: (0xEEF1F5, 0xD6DCE4)
        }
        return LinearGradient(colors: [Color(hex: pair.0), Color(hex: pair.1)], startPoint: .top, endPoint: .bottom)
    }

    static func podiumGlow(_ rank: Int) -> Color {
        switch rank {
        case 1: coral
        case 2: Color(hex: 0x00B4F0)
        case 3: cobalt
        default: shadowInk
        }
    }

    /// The text colour on a podium fill: white on coral and cobalt, deep navy on cyan.
    static func onPodium(_ rank: Int) -> Color {
        switch rank {
        case 1, 3: .white
        case 2: Color(hex: 0x06283A)
        default: Color(hex: inkSoftHex)
        }
    }

    /// Ink or white, whichever reads better on `color`.
    static func text(on color: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return luminance > 0.25 ? Color(hex: inkHex) : .white
    }

    static let cornerRadius: CGFloat = 24
    static let controlRadius: CGFloat = 16
    static let badgeRadius: CGFloat = 14
    static let spacing: CGFloat = 16

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

/// The app's springs, so every surface moves the same way.
enum Motion {
    /// Presses: quick squish, small overshoot on release.
    static let press = Animation.spring(duration: 0.28, bounce: 0.45)
    /// Selection and state changes.
    static let pop = Animation.spring(duration: 0.4, bounce: 0.35)
    /// Score points filling in, one after another.
    static func fill(_ index: Int) -> Animation {
        .spring(duration: 0.5, bounce: 0.3).delay(min(Double(index) * 0.035, 0.4))
    }
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
    /// Headings, names and scores, in San Francisco Rounded so every glyph matches the soft
    /// shapes. Scales with Dynamic Type.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }

    static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Small keys over data ("Ranked with", "System").
    static let dataKey: Font = .system(.caption, design: .rounded, weight: .semibold)
}

// MARK: - Surfaces and buttons

/// Everything behind the content: calm steel, a touch lighter at the top.
struct AmbientBackground: View {
    var body: some View {
        Theme.canvasGradient
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// The gloss on glass: a bright band over the top of the shape, fading by the middle.
struct Gloss<S: Shape>: View {
    var shape: S
    var strength: Double = 0.5

    var body: some View {
        shape.fill(LinearGradient(stops: [.init(color: .white.opacity(strength), location: 0),
                                          .init(color: .white.opacity(0), location: 0.55)],
                                  startPoint: .top, endPoint: .bottom))
            .allowsHitTesting(false)
    }
}

extension View {
    /// A soft, diffuse shadow in `color`.
    func softShadow(_ color: Color = Theme.shadowInk, strength: Double = 1) -> some View {
        shadow(color: color.opacity(0.12 * strength), radius: 22, x: 0, y: 10)
    }

    /// Liquid Glass, for the layer of controls that floats above the content. `tint` colours it
    /// and `interactive` makes it respond to touch. Before iOS 26 it falls back to frosted
    /// material with a gloss and a bright edge.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(tint ?? .clear, in: shape)
                .background { Gloss(shape: shape, strength: 0.45) }
                .background(.ultraThinMaterial, in: shape)
                .overlay { shape.strokeBorder(Theme.rule, lineWidth: 1) }
                .softShadow()
        }
    }

    /// A glossy glass panel on the steel. `shadow` tints its soft shadow; nil drops it.
    func plate<S: InsettableShape>(_ shape: S, fill: Color = Theme.plate, shadow: Color? = Theme.shadowInk,
                                   distance: CGFloat = 0) -> some View {
        background(fill, in: shape)
            .background { Gloss(shape: shape, strength: 0.6) }
            .background(.ultraThinMaterial, in: shape)
            .overlay { shape.strokeBorder(Theme.rule, lineWidth: Theme.ruleWidth) }
            .shadow(color: (shadow ?? .clear).opacity(shadow == Theme.shadowInk ? 0.10 : 0.22), radius: 22, x: 0, y: 10)
    }

    /// Squishes on press and springs back, for anything tappable that isn't a Button style.
    func pressable(_ isPressed: Bool) -> some View {
        scaleEffect(isPressed ? 0.94 : 1)
            .animation(Motion.press, value: isPressed)
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
    var shadow: Color? = Theme.shadowInk

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .plate(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous), shadow: shadow)
    }
}

/// The key panel on a screen: a cobalt-to-ocean glass slab. Its contents render in the dark
/// colour scheme, so the app's ink and surfaces turn white on it.
struct HeroModifier: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        content
            .environment(\.colorScheme, .dark)
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { Gloss(shape: shape, strength: 0.16) }
            .background(Theme.keyGradient, in: shape)
            .overlay { shape.strokeBorder(.white.opacity(0.4), lineWidth: 1) }
            .shadow(color: Theme.cobalt.opacity(0.32), radius: 24, x: 0, y: 14)
    }
}

extension View {
    /// A glass panel. Pass `shadow` to tint its glow (the podium does), or nil for none.
    func card(padding: CGFloat = Theme.spacing, shadow: Color? = Theme.shadowInk) -> some View {
        modifier(CardModifier(padding: padding, shadow: shadow))
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

    func hero(padding: CGFloat = 18) -> some View {
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
            safeAreaInset(edge: .bottom, spacing: 0) { bar.background(.ultraThinMaterial) }
        }
    }

    /// Text input: a glass well with a bright edge.
    func inputField() -> some View {
        padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Theme.plate, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1)
            }
    }
}

/// The cobalt gloss, for the one main action on a screen. On the key panel it turns to
/// white glass with cobalt text, so it still stands out. Squishes on press.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        let onKey = colorScheme == .dark
        configuration.label
            .font(.system(.headline, design: .rounded))
            .foregroundStyle(isEnabled ? (onKey ? Theme.tint : Theme.onTint) : Theme.inkSoft)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.vertical, 13)
            .padding(.horizontal, 18)
            .contentShape(shape)
            .background { Gloss(shape: shape, strength: onKey ? 0.2 : 0.4) }
            .background {
                if !isEnabled { shape.fill(Theme.fill) }
                else if onKey { shape.fill(.white) }
                else { shape.fill(Theme.keyGradient) }
            }
            .overlay { shape.strokeBorder(.white.opacity(0.45), lineWidth: 1) }
            .shadow(color: (onKey ? Color.black : Theme.cobalt).opacity(isEnabled ? (onKey ? 0.15 : 0.35) : 0), radius: 14, x: 0, y: 8)
            .pressable(configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// A glass capsule, for actions beside the primary one.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(isEnabled ? tint : Theme.inkSoft.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Capsule())
            .plate(Capsule())
            .pressable(configuration.isPressed)
    }
}

/// For tappable things that aren't buttons-with-a-look: chips, rows, tiles. Squish only.
struct SquishButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.pressable(configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == SquishButtonStyle {
    static var squish: SquishButtonStyle { SquishButtonStyle() }
}
