import SwiftUI

@main
struct RAV4DashApp: App {
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(model)
        }
    }
}
