import SwiftUI

@main
struct DeconstructedApp: App {
    @State private var model = AppModel(environment: .make())

    init() {
        // Navigation titles use the same serif display face as the rest of the app.
        func serif(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
            let size: CGFloat = style == .largeTitle ? 36 : 18
            let font = UIFont(name: "Optima-Bold", size: size) ?? .preferredFont(forTextStyle: style)
            return UIFontMetrics(forTextStyle: style).scaledFont(for: font)
        }
        let ink = UIColor(hex: Theme.alabasterHex)
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: serif(.largeTitle, weight: .bold), .foregroundColor: ink]
        UINavigationBar.appearance().titleTextAttributes = [.font: serif(.headline, weight: .semibold), .foregroundColor: ink]
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.rose)
                // One look everywhere: dark glass over the jet canvas, sheets included.
                .preferredColorScheme(.dark)
                .task { await model.bootstrap() }
        }
    }
}
