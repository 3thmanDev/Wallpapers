import SwiftUI
import UIKit

@main
struct WallpapersApp: App {
    @StateObject private var store = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // The tab bar and navigation titles are UIKit, so they get the Cairo font here.
        let tabFont = UIFont(name: CairoWeight.semibold.rawValue, size: 11) ?? .systemFont(ofSize: 11, weight: .semibold)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabFont], for: .normal)
        UITabBarItem.appearance().setTitleTextAttributes([.font: tabFont], for: .selected)
        if let titleFont = UIFont(name: CairoWeight.bold.rawValue, size: 17) {
            UINavigationBar.appearance().titleTextAttributes = [.font: titleFont]
        }
        if let largeFont = UIFont(name: CairoWeight.black.rawValue, size: 32) {
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: largeFont]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .appEnvironment()
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { store.save() }
        }
    }
}
