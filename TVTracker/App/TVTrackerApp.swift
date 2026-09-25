import SwiftUI
import SwiftData

@main
struct TVTrackerApp: App {
    init() {
        // كاش أكبر للصور عشان البوسترات ما تنحمل كل مرة
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 512 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [Show.self, Episode.self])
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            UpNextView()
                .tabItem { Label("المتابعة", systemImage: "play.tv.fill") }
            MyShowsView()
                .tabItem { Label("مسلسلاتي", systemImage: "square.grid.2x2.fill") }
            SearchView()
                .tabItem { Label("بحث", systemImage: "magnifyingglass") }
            ProfileView()
                .tabItem { Label("حسابي", systemImage: "person.crop.circle.fill") }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await Library.refreshAll(in: context) }
            }
        }
    }
}
