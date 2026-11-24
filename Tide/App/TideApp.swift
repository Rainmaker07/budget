import SwiftUI
import TideKit

@main
struct TideApp: App {
    @State private var model: AppModel

    init() {
        let persistence = PersistenceController.shared
        if LaunchOptions.isDemo {
            DemoData.populate(persistence.viewContext, mode: LaunchOptions.budgetMode ?? .limits)
        }
        _model = State(initialValue: AppModel(context: persistence.viewContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(\.managedObjectContext, model.context)
        }
    }
}
