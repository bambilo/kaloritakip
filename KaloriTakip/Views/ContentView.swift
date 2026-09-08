import SwiftUI
import SwiftData

struct ContentView: View {
    #if DEBUG
    @State private var selection = ProcessInfo.processInfo.environment["UITEST_TAB"].flatMap(Int.init) ?? 0
    #endif

    init() {
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Theme.inkDeep)
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let baseDescriptor = UIFont.systemFont(ofSize: 34, weight: .medium).fontDescriptor
        let serifDescriptor = baseDescriptor.withDesign(.serif) ?? baseDescriptor
        let serifTitleFont = UIFont(descriptor: serifDescriptor, size: 34)
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Theme.ink)
        navAppearance.largeTitleTextAttributes = [.font: serifTitleFont, .foregroundColor: UIColor(Theme.porcelain)]
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.porcelain)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }

    var body: some View {
        #if DEBUG
        TabView(selection: $selection) {
            AddView().tag(0)
                .tabItem { Label("Ekle", systemImage: "camera") }
            TodayView().tag(1)
                .tabItem { Label("Bugün", systemImage: "circle.dashed") }
            HistoryView().tag(2)
                .tabItem { Label("Geçmiş", systemImage: "chart.xyaxis.line") }
            SettingsView().tag(3)
                .tabItem { Label("Ayarlar", systemImage: "slider.horizontal.3") }
        }
        .tint(Theme.copper)
        #else
        TabView {
            AddView()
                .tabItem { Label("Ekle", systemImage: "camera") }
            TodayView()
                .tabItem { Label("Bugün", systemImage: "circle.dashed") }
            HistoryView()
                .tabItem { Label("Geçmiş", systemImage: "chart.xyaxis.line") }
            SettingsView()
                .tabItem { Label("Ayarlar", systemImage: "slider.horizontal.3") }
        }
        .tint(Theme.copper)
        #endif
    }
}
