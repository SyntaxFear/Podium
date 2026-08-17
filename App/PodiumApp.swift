import SwiftUI

@main
struct PodiumApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .frame(minWidth: 860, minHeight: 520)
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}
