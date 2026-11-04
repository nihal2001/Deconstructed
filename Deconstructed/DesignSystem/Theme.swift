import SwiftUI
import UIKit

/// Palette and type for the app: a press proof on peach stock.
///
/// Content sits on warm peach. Plates are pale cream, ruled in oxblood ink with small corners,
/// and cast a crisp teal offset shadow with no blur, like a second colour printed slightly out
/// of register. Colour is kept for meaning: four contrasting criterion inks for score data,
/// teal for anything you can tap, and a few state colours. The system tab bar and floating
/// map controls stay on Liquid Glass on iOS 26.
///
/// The app is light only.
enum Theme {
    // Stock and ink
    static let stockHex: UInt32 = 0xFBE2D4
    static let plateHex: UInt32 = 0xFFF8F3
    static let inkHex: UInt32 = 0x2A0E08
    static let inkSoftHex: UInt32 = 0x6A4A40
    static let hairlineHex: UInt32 = 0xE7C3B2

    // Inks
    static let tomatoHex: UInt32 = 0xD93A1C
    static let tealHex: UInt32 = 0x0E6E6A
    static let ochreHex: UInt32 = 0xD9961B
    static let ultramarineHex: UInt32 = 0x2E3FA8
    static let plumHex: UInt32 = 0x8A2D63
    static let mossHex: UInt32 = 0x44701A

    static let tomato = Color(hex: tomatoHex)
    static let teal = Color(hex: tealHex)
    static let ochre = Color(hex: ochreHex)
    static let ultramarine = Color(hex: ultramarineHex)
    static let plum = Color(hex: plumHex)
    static let moss = Color(hex: mossHex)

    // Surfaces
    static let canvas = Color(hex: stockHex)
    /// A content panel.
    static let plate = Color(hex: plateHex)
    /// Sunk wells: unselected chips, tracks behind bars.
    static let fill = Color(hex: 0xF6D3C2)
    /// Quiet dividers inside a plate.
    static let hairline = Color(hex: hairlineHex)
    /// The rule round every plate and control.
    static let rule = Color(hex: inkHex)
    static let ruleWidth: CGFloat = 2
    /// The offset shadow under plates.
    static let shadowInk = teal
    static let shadowOffset: CGFloat = 5

    // Text
    static let ink = Color(hex: inkHex)
    static let inkSoft = Color(hex: inkSoftHex)
    /// Text on a teal fill.
    static let onTint = Color.white

    // Roles. Text-safe on the plate and the stock (4.5:1 or better).
    /// The one interactive colour: buttons, links, selection, the tab bar.
    static let tint = teal
    /// Done, visited, balanced.
    static let positive = moss
    /// Saved / want to try.
    static let saved = ultramarine
    /// Problems and anything that needs attention, including the demo marker.
    static let warning = Color(hex: 0xB52E12)

    /// One colour per criterion, by position, so a criterion keeps its colour everywhere its
    /// score appears. Neighbours contrast in hue and value. Colour is never the only cue:
    /// names and numbers sit beside it.
    static let criterionColors: [Color] = {
        let base = [tomato, teal, ochre, ultramarine, plum, moss]
        return base + base.map { $0.opacity(0.55) }
    }()

    static func criterionColor(_ index: Int) -> Color {
        criterionColors[index % criterionColors.count]
    }

    /// Ink or white, whichever reads better on `color`.
    static func text(on color: Color) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return luminance > 0.179 ? ink : .white
    }

    static let cornerRadius: CGFloat = 4
    static let controlRadius: CGFloat = 4
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
    /// Headings, names and scores. One grotesque carries the whole app: San Francisco, which
    /// scales with Dynamic Type. Scores are set heavy and tracked in.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, weight: weight)
    }

    static func display(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight)
    }

    /// Small uppercase keys over data ("RANKED WITH", "VISITS"). Pair with `.tracking(0.8)`.
    static let dataKey: Font = .system(.caption2, design: .monospaced, weight: .medium)
}

// MARK: - Surfaces and buttons

/// Everything behind the content: plain peach stock.
struct AmbientBackground: View {
    var body: some View {
        Theme.canvas
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

extension View {
    /// The crisp offset shadow: a solid copy of the shape, shifted down and right, no blur.
    func offsetShadow<S: Shape>(_ shape: S, color: Color = Theme.shadowInk, distance: CGFloat = Theme.shadowOffset) -> some View {
        background { shape.fill(color).offset(x: distance, y: distance) }
    }

    /// Liquid Glass, for the layer of controls that floats above the content. `tint` colours it
    /// and `interactive` makes it respond to touch. Before iOS 26 it falls back to a solid
    /// plate with the ink rule.
    @ViewBuilder
    func liquidGlass<S: InsettableShape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(tint ?? Theme.plate, in: shape)
                .overlay { shape.strokeBorder(Theme.rule, lineWidth: Theme.ruleWidth) }
                .background { shape.fill(Theme.ink).offset(x: 3, y: 3) }
        }
    }

    /// A ruled plate on the stock with its offset shadow. `fill` washes it; `shadow` nil drops it.
    func plate<S: InsettableShape>(_ shape: S, fill: Color = Theme.plate, shadow: Color? = Theme.shadowInk,
                                   distance: CGFloat = Theme.shadowOffset) -> some View {
        background(fill, in: shape)
            .overlay { shape.strokeBorder(Theme.rule, lineWidth: Theme.ruleWidth) }
            .background { if let shadow { shape.fill(shadow).offset(x: distance, y: distance) } }
            .padding(.trailing, shadow == nil ? 0 : distance)
            .padding(.bottom, shadow == nil ? 0 : distance)
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

/// The most important plate on a screen: a deeper offset in ochre, which no podium uses.
struct HeroModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .plate(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous), shadow: Theme.ochre, distance: 6)
    }
}

extension View {
    /// A ruled plate. Pass `shadow: nil` for plates in long lists that shouldn't each cast one.
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

    func hero(padding: CGFloat = 16) -> some View {
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
            safeAreaInset(edge: .bottom, spacing: 0) {
                bar.background(Theme.canvas).overlay(alignment: .top) { Theme.rule.frame(height: 1.5) }
            }
        }
    }

    /// Text input: a plate well with the ink rule, in place of the system's rounded border.
    func inputField() -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.plate, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.rule, lineWidth: 1.5)
            }
    }
}

/// Teal, for the one main action on a screen, with a crisp oxblood offset. Pressing it pushes
/// the button down onto its shadow.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        let pressed = configuration.isPressed
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Theme.onTint : Theme.inkSoft)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .contentShape(shape)
            .background(isEnabled ? Theme.tint : Theme.fill, in: shape)
            .overlay { shape.strokeBorder(Theme.rule, lineWidth: Theme.ruleWidth) }
            .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
            .background { shape.fill(isEnabled ? Theme.ink : Theme.hairline).offset(x: 3, y: 3) }
            .padding(.trailing, 3).padding(.bottom, 3)
            .animation(.snappy(duration: 0.12), value: pressed)
    }
}

/// A cream capsule with the ink rule, for actions beside the primary one.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var tint: Color = Theme.ink

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule()
        let pressed = configuration.isPressed
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? tint : Theme.inkSoft.opacity(0.7))
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .contentShape(shape)
            .background(pressed ? Theme.fill : Theme.plate, in: shape)
            .overlay { shape.strokeBorder(isEnabled ? Theme.rule : Theme.hairline, lineWidth: 1.5) }
            .offset(x: pressed ? 2 : 0, y: pressed ? 2 : 0)
            .background { shape.fill(isEnabled ? Theme.ink : .clear).offset(x: 2, y: 2) }
            .padding(.trailing, 2).padding(.bottom, 2)
            .animation(.snappy(duration: 0.12), value: pressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
