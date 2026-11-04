import SwiftUI

@main
struct DeconstructedApp: App {
    @State private var model = AppModel(environment: .make())

    init() {
        // Navigation titles in the app's one grotesque, oxblood ink on peach, set heavy and
        // tracked in like a proof's headings.
        let ink = UIColor(hex: Theme.inkHex)
        let large = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: .systemFont(ofSize: 34, weight: .heavy))
        let inline = UIFontMetrics(forTextStyle: .headline).scaledFont(for: .systemFont(ofSize: 17, weight: .bold))
        UINavigationBar.appearance().largeTitleTextAttributes = [.font: large, .foregroundColor: ink, .kern: -0.6]
        UINavigationBar.appearance().titleTextAttributes = [.font: inline, .foregroundColor: ink]

        // Search fields are cream plates, not system grey.
        UISearchTextField.appearance().backgroundColor = UIColor(hex: Theme.plateHex)

        // Before Liquid Glass, the bars are peach stock with an ink rule, not system grey.
        if #unavailable(iOS 26) {
            let stock = UIColor(hex: Theme.stockHex)
            let nav = UINavigationBarAppearance()
            nav.configureWithOpaqueBackground()
            nav.backgroundColor = stock
            nav.shadowColor = ink
            nav.largeTitleTextAttributes = [.font: large, .foregroundColor: ink, .kern: -0.6]
            nav.titleTextAttributes = [.font: inline, .foregroundColor: ink]
            let navEdge = UINavigationBarAppearance()
            navEdge.configureWithTransparentBackground()
            navEdge.largeTitleTextAttributes = nav.largeTitleTextAttributes
            navEdge.titleTextAttributes = nav.titleTextAttributes
            UINavigationBar.appearance().standardAppearance = nav
            UINavigationBar.appearance().compactAppearance = nav
            UINavigationBar.appearance().scrollEdgeAppearance = navEdge

            let tab = UITabBarAppearance()
            tab.configureWithOpaqueBackground()
            tab.backgroundColor = UIColor(hex: Theme.plateHex)
            tab.shadowColor = ink
            let item = tab.stackedLayoutAppearance
            item.normal.iconColor = UIColor(hex: Theme.inkSoftHex)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(hex: Theme.inkSoftHex)]
            UITabBar.appearance().standardAppearance = tab
            UITabBar.appearance().scrollEdgeAppearance = tab
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.tint)
                // One look everywhere: ruled plates on peach stock, sheets included.
                .preferredColorScheme(.light)
                .task { await model.bootstrap() }
        }
    }
}
