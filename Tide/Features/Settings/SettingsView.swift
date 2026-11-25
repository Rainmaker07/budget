import CoreData
import SwiftUI
import TideKit

/// Settings: household, budgeting style, categories, places, about.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [SortDescriptor(\Member.sortOrder)])
    private var members: FetchedResults<Member>

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Household") {
                    HouseholdNameField(household: model.household)
                    ForEach(members, id: \.objectID) { member in
                        MemberRow(member: member)
                    }
                    .onDelete(perform: deleteMembers)
                    Button("Add person", systemImage: "person.badge.plus", action: addMember)
                }

                Section {
                    Picker("Budgeting style", selection: $model.budgetMode) {
                        ForEach(BudgetMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } footer: {
                    Text(model.budgetMode.summary)
                }

                Section {
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        Label("Categories", systemImage: "square.grid.2x2.fill")
                    }
                    NavigationLink {
                        PlacesScreen()
                    } label: {
                        Label("Places", systemImage: "storefront.fill")
                    }
                    LabeledContent {
                        Text(model.currency.rawValue)
                    } label: {
                        Label("Main currency", systemImage: "eurosign.circle.fill")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: AppInfo.version)
                    LabeledContent("Build", value: AppInfo.build)
                }
            }
            .scrollContentBackground(.hidden)
            .background { TideBackground(health: model.snapshot.summary.health) }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") {
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear { try? context.save() }
    }

    private func addMember() {
        let member = Member(context: context)
        member.name = "Partner"
        member.colorName = TidePalette.names[(members.count * 3 + 3) % TidePalette.names.count]
        member.sortOrder = Int16(members.count)
        member.household = model.household
        try? context.save()
    }

    private func deleteMembers(at offsets: IndexSet) {
        // Always keep at least one person.
        guard members.count - offsets.count >= 1 else { return }
        for index in offsets { context.delete(members[index]) }
        try? context.save()
    }
}

private struct HouseholdNameField: View {
    @ObservedObject var household: Household

    var body: some View {
        TextField("Budget name", text: Binding(
            get: { household.name ?? "" },
            set: { household.name = $0 }
        ))
        .font(.headline)
    }
}

private struct MemberRow: View {
    @ObservedObject var member: Member
    @Environment(\.managedObjectContext) private var context

    var body: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(TidePalette.names, id: \.self) { name in
                    Button(name.capitalized) {
                        member.colorName = name
                        try? context.save()
                    }
                }
            } label: {
                MemberAvatar(member: member, size: 30)
            }
            TextField("Name", text: Binding(
                get: { member.name ?? "" },
                set: { member.name = $0 }
            ))
            .submitLabel(.done)
            .onSubmit { try? context.save() }
        }
    }
}
