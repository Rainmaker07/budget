import CoreData
import SwiftUI
import TideKit

/// A Core Data object wrapped for `.sheet(item:)`.
struct ObjectRef<T: NSManagedObject>: Identifiable {
    let object: T
    var id: NSManagedObjectID { object.objectID }
}

/// What the category editor is creating or editing.
enum CategoryEditorTarget: Identifiable {
    case new(kind: CategoryKind, parent: BudgetCategory?)
    case edit(BudgetCategory)

    var id: String {
        switch self {
        case .new(let kind, let parent): "new-\(kind.rawValue)-\(parent?.objectID.uriRepresentation().absoluteString ?? "top")"
        case .edit(let category): category.objectID.uriRepresentation().absoluteString
        }
    }
}

/// All categories, one section per kind. Drag to reorder, tap to open,
/// swipe to hide or delete.
struct CategoriesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(sortDescriptors: [SortDescriptor(\BudgetCategory.sortOrder)])
    private var categories: FetchedResults<BudgetCategory>

    @State private var editorTarget: CategoryEditorTarget?
    @State private var deleting: ObjectRef<BudgetCategory>?

    var body: some View {
        List {
            ForEach(CategoryKind.allCases) { kind in
                Section {
                    ForEach(tops(kind), id: \.objectID) { category in
                        NavigationLink {
                            CategoryGroupView(category: category)
                        } label: {
                            CategoryRow(category: category,
                                        detail: subtitle(for: category))
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                deleting = ObjectRef(object: category)
                            }
                            Button(category.isHidden ? "Show" : "Hide",
                                   systemImage: category.isHidden ? "eye" : "eye.slash") {
                                CategoryStore.setHidden(!category.isHidden, category, context: context)
                            }
                            .tint(.gray)
                        }
                    }
                    .onMove { from, to in
                        var list = tops(kind)
                        list.move(fromOffsets: from, toOffset: to)
                        CategoryStore.applyOrder(list, context: context)
                    }

                    Button {
                        editorTarget = .new(kind: kind, parent: nil)
                    } label: {
                        Label("Add category", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Label(kind.title, systemImage: kind.systemImage)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { TideBackground(health: model.snapshot.summary.health) }
        .navigationTitle("Categories")
        .toolbar { EditButton() }
        .sheet(item: $editorTarget) { target in
            CategoryEditorView(target: target)
        }
        .sheet(item: $deleting) { ref in
            DeleteCategorySheet(category: ref.object)
        }
    }

    private func tops(_ kind: CategoryKind) -> [BudgetCategory] {
        categories.filter { $0.kind == kind && $0.parent == nil && !$0.isDeleted }
    }

    private func subtitle(for category: BudgetCategory) -> String {
        let count = category.allChildren.count
        let subs = count == 1 ? "1 subcategory" : "\(count) subcategories"
        return category.isHidden ? "Hidden · \(subs)" : subs
    }
}

/// Icon, name and a detail line.
struct CategoryRow: View {
    @ObservedObject var category: BudgetCategory
    var detail: String?

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(systemName: category.symbol, color: category.color, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.displayName)
                    .font(.body.weight(.medium))
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(category.isEffectivelyHidden ? 0.5 : 1)
    }
}

/// One top-level category and its subcategories.
struct CategoryGroupView: View {
    @ObservedObject var category: BudgetCategory
    @Environment(AppModel.self) private var model
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FetchRequest private var children: FetchedResults<BudgetCategory>
    @State private var editorTarget: CategoryEditorTarget?
    @State private var deleting: ObjectRef<BudgetCategory>?

    init(category: BudgetCategory) {
        self.category = category
        _children = FetchRequest(
            sortDescriptors: [SortDescriptor(\BudgetCategory.sortOrder)],
            predicate: NSPredicate(format: "parent == %@", category)
        )
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    IconBadge(systemName: category.symbol, color: category.color, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.displayName)
                            .font(.title2.weight(.semibold))
                        Text(category.kind.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") { editorTarget = .edit(category) }
                        .buttonStyle(.glass)
                }
                .listRowBackground(Color.clear)
            }

            Section("Subcategories") {
                ForEach(children, id: \.objectID) { child in
                    Button {
                        editorTarget = .edit(child)
                    } label: {
                        CategoryRow(category: child, detail: detail(for: child))
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleting = ObjectRef(object: child)
                        }
                        Button(child.isHidden ? "Show" : "Hide",
                               systemImage: child.isHidden ? "eye" : "eye.slash") {
                            CategoryStore.setHidden(!child.isHidden, child, context: context)
                        }
                        .tint(.gray)
                    }
                }
                .onMove { from, to in
                    var list = Array(children)
                    list.move(fromOffsets: from, toOffset: to)
                    CategoryStore.applyOrder(list, context: context)
                }

                Button {
                    editorTarget = .new(kind: category.kind, parent: category)
                } label: {
                    Label("Add subcategory", systemImage: "plus.circle.fill")
                }
            }

            Section {
                Button(category.isHidden ? "Show category" : "Hide category",
                       systemImage: category.isHidden ? "eye" : "eye.slash") {
                    CategoryStore.setHidden(!category.isHidden, category, context: context)
                }
                Button("Delete category", systemImage: "trash", role: .destructive) {
                    deleting = ObjectRef(object: category)
                }
            } footer: {
                Text("Hidden categories disappear from pickers but keep their history in totals and reports.")
            }
        }
        .scrollContentBackground(.hidden)
        .background { TideBackground(health: model.snapshot.summary.health) }
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(item: $editorTarget) { target in
            CategoryEditorView(target: target)
        }
        .sheet(item: $deleting) { ref in
            DeleteCategorySheet(category: ref.object) {
                if ref.object == category || category.isDeleted { dismiss() }
            }
        }
    }

    private func detail(for child: BudgetCategory) -> String {
        let count = CategoryStore.transactionCount(child)
        let text = count == 1 ? "1 transaction" : "\(count) transactions"
        return child.isHidden ? "Hidden · \(text)" : text
    }
}
