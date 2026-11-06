import SwiftUI

@main
struct DeconstructedApp: App {
    @State private var model = AppModel(environment: .make())

    init() {
        // Navigation titles in San Francisco Rounded, ink on steel.
        func rounded(_ size: CGFloat, _ weight: UIFont.Weight, _ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: weight)
            let font = base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: size) } ?? base
            return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
        }
        let ink = UIColor(hex: Theme.inkHex)
        let large = rounded(34, .bold, .largeTitle)
        let inline = rounded(17, .semibold, .headline)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: large, .foregroundColor: ink]
        UINavigationBar.appearance().titleTextAttributes = [.font: inline, .foregroundColor: ink]

        // Before Liquid Glass, the bars are frosted glass with a soft edge, and the selected tab
        // sits on a glossy cobalt capsule behind its icon.
        if #unavailable(iOS 26) {
            let nav = UINavigationBarAppearance()
            nav.configureWithDefaultBackground()
            nav.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
            nav.shadowColor = .clear
            nav.largeTitleTextAttributes = [.font: large, .foregroundColor: ink]
            nav.titleTextAttributes = [.font: inline, .foregroundColor: ink]
            let navEdge = UINavigationBarAppearance()
            navEdge.configureWithTransparentBackground()
            navEdge.largeTitleTextAttributes = nav.largeTitleTextAttributes
            navEdge.titleTextAttributes = nav.titleTextAttributes
            UINavigationBar.appearance().standardAppearance = nav
            UINavigationBar.appearance().compactAppearance = nav
            UINavigationBar.appearance().scrollEdgeAppearance = navEdge

            let tab = UITabBarAppearance()
            tab.configureWithDefaultBackground()
            tab.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialLight)
            tab.backgroundColor = UIColor.white.withAlphaComponent(0.72)
            tab.shadowColor = nil
            tab.shadowImage = Self.tabEdge()
            tab.selectionIndicatorImage = Self.tabCapsule()
            let soft = UIColor(hex: Theme.inkSoftHex)
            for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
                item.normal.iconColor = soft
                item.normal.titleTextAttributes = [.foregroundColor: soft, .font: rounded(10, .medium, .caption2)]
                item.selected.iconColor = .white
                item.selected.titleTextAttributes = [.foregroundColor: UIColor(Theme.tint), .font: rounded(10, .bold, .caption2)]
            }
            UITabBar.appearance().selectionIndicatorImage = tab.selectionIndicatorImage
            UITabBar.appearance().standardAppearance = tab
            UITabBar.appearance().scrollEdgeAppearance = tab
        }

        // Search fields are glass, not system grey.
        UISearchTextField.appearance().backgroundColor = UIColor.white.withAlphaComponent(0.7)
    }

    /// The selected tab's capsule, behind the icon only (the label stays below it, in cobalt).
    /// Drawn at the tab bar's height with fixed margins, so only a 1pt middle column stretches.
    private static func tabCapsule() -> UIImage {
        let size = CGSize(width: 72, height: 49)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(x: 12, y: 3, width: 48, height: 30)
            UIBezierPath(roundedRect: rect, cornerRadius: 15).addClip()
            let colors = [UIColor(hex: 0x3A6BF0).cgColor, UIColor(hex: 0x0B6FB8).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                                                     end: CGPoint(x: rect.maxX, y: rect.maxY), options: [])
            }
            UIColor.white.withAlphaComponent(0.3).setFill()
            UIBezierPath(rect: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.45)).fill()
        }
        return image.resizableImage(withCapInsets: UIEdgeInsets(top: 24, left: 35, bottom: 24, right: 36))
    }

    /// A soft fade above the tab bar instead of a hairline.
    private static func tabEdge() -> UIImage {
        let size = CGSize(width: 1, height: 10)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(hex: 0x1E2836).withAlphaComponent(0).cgColor,
                          UIColor(hex: 0x1E2836).withAlphaComponent(0.08).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 10), options: [])
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.tint)
                .fontDesign(.rounded)
                // One look everywhere: glossy glass on steel, sheets included.
                .preferredColorScheme(.light)
                .task { await model.bootstrap() }
        }
    }
}
