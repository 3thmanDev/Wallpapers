import SwiftUI

enum AppTab: Hashable {
    case wallpapers
    case twitter
    case link
}

/// The three tabs. Built with the iOS 26 SDK, the system draws this tab bar in Liquid Glass.
struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var tab = AppTab.wallpapers

    var body: some View {
        TabView(selection: $tab) {
            LibraryView(onImport: { tab = .twitter }, onAddLink: { tab = .link })
                .tabItem { Label("خلفياتي", systemImage: "photo.stack") }
                .badge(store.library.pendingCount)
                .tag(AppTab.wallpapers)
            ImportView(store: store, onDone: { tab = .wallpapers })
                .tabItem { Label("تويتر", systemImage: "arrow.down.circle") }
                .tag(AppTab.twitter)
            AddLinkView(onDone: { tab = .wallpapers })
                .tabItem { Label("بالرابط", systemImage: "link") }
                .tag(AppTab.link)
        }
        .minimizesTabBarOnScroll()
    }
}

extension View {
    /// On iOS 26 the glass tab bar shrinks while scrolling down the grid; older systems keep the normal bar.
    @ViewBuilder
    func minimizesTabBarOnScroll() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Liquid Glass on iOS 26, frosted material before it.
    @ViewBuilder
    func glassBackground<S: Shape>(_ shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
        #else
        background(.ultraThinMaterial, in: shape)
        #endif
    }
}
