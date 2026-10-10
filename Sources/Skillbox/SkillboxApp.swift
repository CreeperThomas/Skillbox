import SwiftUI

@main
struct SkillboxApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            LibraryView(model: model).frame(minWidth: 1080, minHeight: 680)
        }.defaultSize(width: 1320, height: 840)
        Settings { SettingsView(model: model) }
    }
}
