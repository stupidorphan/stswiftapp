import SwiftUI
import SwiftData
import Observation

@main
struct stswiftappApp: App {
    @State private var appViewModel = STAppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appViewModel)
                .onAppear {
                    appViewModel.loadConfiguration()
                }
        }
    }
}
