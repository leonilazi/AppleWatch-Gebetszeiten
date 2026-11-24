import SwiftUI

@main struct MyApp: App {
    @StateObject private var standort = StandortManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(standort)
        }
    }
}
