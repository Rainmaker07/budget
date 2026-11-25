import SwiftUI
import TideKit

/// Creates or edits a category or subcategory: name, icon, color, and for
/// subcategories which category it belongs to.
struct CategoryEditorView: View {
    let target: CategoryEditorTarget

    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var icon = "circle.fill"
    @State private var colorName = "blue"
    @State private var parent: BudgetCategory?
    @FocusState private var nameFocused: Bool

    private var kind: CategoryKind {
        switch target {
        case .new(let kind, let parent): parent?.kind ?? kind
        case .edit(let category): category.kind
        }
    }

    /// Subcategory (has or will have a parent) vs top-level category.
    private var isSubcategory: Bool {
        switch target {
        case .new(_, let parent): parent != nil
        case .edit(let category): category.parent != nil
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var previewColor: Color {
        TidePalette.color(named: isSubcategory ? parent?.colorName : colorName)
    }

    private var canSave: Bool {
        !PlaceName.clean(name).isEmpty && (!isSubcategory || parent != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        IconBadge(systemName: icon, color: previewColor, size: 48)
                        TextField(isSubcategory ? "Subcategory name" : "Category name", text: $name)
                            .font(.title3.weight(.semibold))
                            .focused($nameFocused)
                            .submitLabel(.done)
                    }
                }

                if isSubcategory {
                    Section {
                        Picker("Belongs to", selection: $parent) {
                            ForEach(model.household.topCategories(kind, includeHidden: true), id: \.objectID) { top in
                                Label(top.displayName, systemImage: top.symbol).tag(Optional(top))
                            }
                        }
                    } footer: {
                        Text("Moving a subcategory keeps all its transactions and budgets.")
                    }
                } else {
                    Section("Color") {
                        ColorSwatchPicker(selection: $colorName)
                            .padding(.vertical, 4)
                    }
                }

                Section("Icon") {
                    IconPicker(selection: $icon, color: previewColor)
                        .padding(.vertical, 4)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", systemImage: "checkmark", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var title: String {
        switch (isNew, isSubcategory) {
        case (true, true): "New subcategory"
        case (true, false): "New category"
        case (false, true): "Edit subcategory"
        case (false, false): "Edit category"
        }
    }

    private func load() {
        switch target {
        case .new(_, let parent):
            self.parent = parent
            icon = parent?.symbol ?? "circle.fill"
            colorName = parent?.colorName ?? "blue"
            nameFocused = true
        case .edit(let category):
            name = category.displayName
            icon = category.symbol
            colorName = category.colorName ?? "blue"
            parent = category.parent
        }
    }

    private func save() {
        switch target {
        case .new(let kind, _):
            CategoryStore.create(name: name, kind: kind, icon: icon, colorName: colorName,
                                 parent: parent, household: model.household, context: context)
        case .edit(let category):
            category.name = PlaceName.clean(name)
            category.icon = icon
            if let parent, category.parent != nil, parent != category.parent {
                CategoryStore.move(category, to: parent, context: context)
            }
            if category.parent == nil {
                CategoryStore.setColor(colorName, for: category, context: context)
            }
            try? context.save()
        }
        dismiss()
    }
}

/// Confirms deleting a category. If it has transactions, they're moved to
/// another category first — or the category can be hidden instead.
struct DeleteCategorySheet: View {
    @ObservedObject var category: BudgetCategory
    var onFinish: () -> Void = {}

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var target: BudgetCategory?

    private var count: Int { CategoryStore.transactionCount(category) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        IconBadge(systemName: category.symbol, color: category.color, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Delete \(category.displayName)?")
                                .font(.headline)
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if count > 0 {
                    Section("Move its transactions to") {
                        ForEach(CategoryStore.reassignTargets(for: category), id: \.objectID) { option in
                            Button {
                                target = option
                            } label: {
                                HStack {
                                    CategoryRow(category: option, detail: option.parent?.displayName)
                                    Spacer()
                                    if target == option {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button(count > 0 ? "Move \(count) & delete" : "Delete", role: .destructive) {
                        CategoryStore.delete(category, movingTransactionsTo: target, context: context)
                        finish()
                    }
                    .disabled(count > 0 && target == nil)

                    if count > 0 {
                        Button("Hide instead") {
                            CategoryStore.setHidden(true, category, context: context)
                            finish()
                        }
                    }
                } footer: {
                    if count > 0 {
                        Text("Hiding keeps the category and its history in reports, but removes it from pickers.")
                    }
                }
            }
            .navigationTitle("Delete category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var summary: String {
        let subs = category.allChildren.count
        var parts: [String] = []
        parts.append(count == 1 ? "1 transaction" : "\(count) transactions")
        if subs > 0 { parts.append(subs == 1 ? "1 subcategory" : "\(subs) subcategories") }
        return parts.joined(separator: " · ")
    }

    private func finish() {
        dismiss()
        onFinish()
    }
}
