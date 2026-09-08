import SwiftUI
import SwiftData

@main
struct KaloriTakipApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([FoodLog.self, Favorite.self, UserProfile.self])
        #if DEBUG
        let seedDemo = ProcessInfo.processInfo.arguments.contains("-seedDemoData")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: seedDemo)
        #else
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        #endif
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            #if DEBUG
            if seedDemo { DemoData.seed(into: container.mainContext) }
            #endif
            return container
        } catch {
            fatalError("ModelContainer oluşturulamadı: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, Locale(identifier: "tr_TR"))
        }
        .modelContainer(sharedModelContainer)
    }
}
