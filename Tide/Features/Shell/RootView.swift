import SwiftUI
import TideKit

enum AppTab: String, CaseIterable, Hashable {
    case home, activity, plan, wealth, reports
}

/// The five-tab shell. The "Add transaction" pill sits in the tab bar's
/// glass accessory slot and morphs into the Quick Add sheet.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = LaunchOptions.initialTab
    @State private var showsQuickAdd = false
    @Namespace private var namespace

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "drop.fill", value: AppTab.home) {
                HomeView()
            }
            Tab("Activity", systemImage: "list.bullet.rectangle.fill", value: AppTab.activity) {
                ActivityView()
            }
            Tab("Plan", systemImage: "chart.pie.fill", value: AppTab.plan) {
                ComingSoonView(feature: .plan)
            }
            Tab("Wealth", systemImage: "building.columns.fill", value: AppTab.wealth) {
                ComingSoonView(feature: .wealth)
            }
            Tab("Reports", systemImage: "chart.xyaxis.line", value: AppTab.reports) {
                ComingSoonView(feature: .reports)
            }
        }
        .tint(TidePalette.accent(for: model.snapshot.summary.health))
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            QuickAddAccessory { showsQuickAdd = true }
                .matchedTransitionSource(id: "quickAdd", in: namespace)
        }
        .sheet(isPresented: $showsQuickAdd) {
            EntryEditorView(mode: .new)
                .navigationTransition(.zoom(sourceID: "quickAdd", in: namespace))
        }
        .task {
            if LaunchOptions.opensQuickAdd { showsQuickAdd = true }
        }
    }
}

/// The glass pill above the tab bar. Collapses to an icon when the tab bar
/// minimizes on scroll.
struct QuickAddAccessory: View {
    var action: () -> Void
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                if placement != .inline {
                    Text("Add transaction")
                        .font(.body.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add transaction")
    }
}

#Preview {
    RootView()
        .environment(AppModel(context: PersistenceController.preview.viewContext))
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
