import SwiftUI

@main
@MainActor
struct DredfitApp: App {
    // Unit tests run hosted in this app, and a real store would load the
    // user's state file and write the App Group snapshot before the first
    // test; the tests build their own. UI tests launch the app as a separate
    // process without this variable, so they still get the real store.
    @State private var store: AppStore? =
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
            ? AppStore() : nil

    var body: some Scene {
        WindowGroup {
            if let store {
                RootView()
                    .environment(store)
            }
        }
    }
}
