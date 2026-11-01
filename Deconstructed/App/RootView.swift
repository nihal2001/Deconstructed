import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.phase {
            case .launching:
                ZStack {
                    AmbientBackground()
                    ProgressView().controlSize(.large)
                }
            case .signedOut:
                SignInView()
            case .unavailable:
                ReconnectView()
            case .signedIn:
                if model.hasAcceptedTerms {
                    MainTabs()
                } else {
                    TermsGateView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.phase)
        .toast($model.toast)
    }
}

/// Shown at launch when a signed-in person's session or data can't be reached.
struct ReconnectView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            AmbientBackground()
            VStack(alignment: .leading, spacing: Theme.spacing) {
                Text("Can't connect")
                    .font(.display(.largeTitle, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("You're still signed in. Deconstructed needs a connection to load your restaurants, and it will carry on when one is back.")
                    .font(.body)
                    .foregroundStyle(Theme.inkSoft)
                AsyncButton("Try again") { await model.bootstrap() }
                    .buttonStyle(.primary)
                Button("Sign out") { Task { await model.signOut() } }
                    .buttonStyle(.secondary)
            }
            .padding(Theme.spacing)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if !Task.isCancelled { await model.bootstrap() }
            }
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if #available(iOS 26, *) {
            // The ribbon rides on the tab bar, so it never covers a navigation bar.
            if model.isDemo {
                tabs.tabBarMinimizeBehavior(.onScrollDown).tabViewBottomAccessory { DemoRibbon() }
            } else {
                tabs.tabBarMinimizeBehavior(.onScrollDown)
            }
        } else {
            // The ribbon sits above the tabs so it never covers a navigation bar.
            VStack(spacing: 0) {
                if model.isDemo {
                    DemoRibbon()
                        .padding(.vertical, 5)
                        .background { Theme.canvas.ignoresSafeArea(edges: .top) }
                }
                tabs
            }
        }
    }

    private var tabs: some View {
        @Bindable var model = model
        return TabView(selection: $model.selectedTab) {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
                .tag(AppTab.discover)
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(AppTab.map)
            RankingsView()
                .tabItem { Label("Rankings", systemImage: "list.number") }
                .tag(AppTab.rankings)
            FriendsView()
                .tabItem { Label("Friends", systemImage: "person.2") }
                .tag(AppTab.friends)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
    }
}

/// Always visible in the demo, on every tab.
struct DemoRibbon: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "theatermasks.fill").imageScale(.small).foregroundStyle(Theme.warning)
            // The tab bar's accessory narrows when the bar minimises.
            ViewThatFits(in: .horizontal) {
                Text("Demo mode · fictional restaurants and people")
                Text("Demo mode")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary) // the tab bar's glass turns light over the map, so this must adapt
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Demo mode. Restaurants and people shown are fictional.")
    }
}

/// Destinations shared by every tab's navigation stack.
enum Route: Hashable {
    case restaurant(placeID: String)
    case visit(Visit, author: UserProfile?)
    case user(UserProfile)
    case rankingSystems
    case system(UUID)
}

extension View {
    func appRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .restaurant(let placeID): RestaurantProfileView(placeID: placeID)
            case .visit(let visit, let author): VisitDetailView(visitID: visit.id, snapshot: visit, author: author)
            case .user(let profile): UserProfileView(user: profile)
            case .rankingSystems: RankingSystemsView()
            case .system(let id): SystemDetailView(systemID: id)
            }
        }
    }
}
