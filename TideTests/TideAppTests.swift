import CoreData
import Foundation
import Testing
import TideKit
@testable import Tide

/// An in-memory household with the starter categories.
@MainActor
private struct Fixture {
    let controller = PersistenceController(inMemory: true)
    var context: NSManagedObjectContext { controller.viewContext }
    let household: Household

    init() {
        household = HouseholdBootstrap.ensureHousehold(in: controller.viewContext)
    }

    func category(_ name: String) -> BudgetCategory {
        household.categoryList.first { $0.name == name }!
    }

    @discardableResult
    func entry(_ amount: Decimal, place: String? = nil, category: String, kind: EntryKind = .expense,
               date: Date = .now) -> LedgerEntry {
        let entry = LedgerEntry(context: context)
        entry.kind = kind
        entry.date = date
        entry.baseAmount = amount.number
        entry.originalAmount = amount.number
        entry.category = self.category(category)
        entry.household = household
        if let place {
            entry.place = PlaceStore.findOrCreate(named: place, in: household, context: context)
            entry.payee = entry.place?.name
        }
        try? context.save()
        return entry
    }
}

@Suite("Store migration")
@MainActor
struct MigrationTests {
    @Test func upgradesVersion1StoreAndLinksPlaces() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tide.sqlite")

        // Write a store the way Tide 0.1.0 did.
        let version1 = try #require(TideModel.history.last)
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: version1)
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url,
                                           options: StoreMigrator.storeOptions)
        let oldContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        oldContext.persistentStoreCoordinator = coordinator
        let household = NSEntityDescription.insertNewObject(forEntityName: "Household", into: oldContext)
        household.setValue("Old budget", forKey: "name")
        for payee in ["Rewe", "REWE ", "Bakery"] {
            let entry = NSEntityDescription.insertNewObject(forEntityName: "LedgerEntry", into: oldContext)
            entry.setValue(payee, forKey: "payee")
            entry.setValue(NSDecimalNumber(string: "12.50"), forKey: "baseAmount")
            entry.setValue(Date.now, forKey: "date")
            entry.setValue(household, forKey: "household")
        }
        try oldContext.save()
        for store in coordinator.persistentStores { try coordinator.remove(store) }

        #expect(try StoreMigrator.migrateIfNeeded(storeAt: url))
        #expect(try StoreMigrator.migrateIfNeeded(storeAt: url) == false)

        let controller = PersistenceController(storeURL: url)
        let context = controller.viewContext
        let households = try context.fetch(NSFetchRequest<Household>(entityName: "Household"))
        #expect(households.count == 1)
        #expect(households.first?.name == "Old budget")

        PlaceStore.backfill(households[0], context: context)
        let places = PlaceStore.all(in: households[0], context: context)
        #expect(Set(places.map(\.displayName)) == ["Rewe", "Bakery"])
        let rewe = try #require(places.first { $0.displayName == "Rewe" })
        #expect(rewe.entryList.count == 2)

        // Close the store before the temporary folder is deleted.
        let storeCoordinator = controller.container.persistentStoreCoordinator
        for store in storeCoordinator.persistentStores { try storeCoordinator.remove(store) }
    }
}

@Suite("Store migration v2")
@MainActor
struct MigrationV2Tests {
    @Test func upgradesVersion2StoreKeepingPlaces() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tide.sqlite")

        let version2 = try #require(TideModel.history.first { $0.entitiesByName["Place"] != nil })
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: version2)
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url,
                                           options: StoreMigrator.storeOptions)
        let oldContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        oldContext.persistentStoreCoordinator = coordinator
        let household = NSEntityDescription.insertNewObject(forEntityName: "Household", into: oldContext)
        let place = NSEntityDescription.insertNewObject(forEntityName: "Place", into: oldContext)
        place.setValue("Rewe", forKey: "name")
        place.setValue(household, forKey: "household")
        let goal = NSEntityDescription.insertNewObject(forEntityName: "SavingsGoal", into: oldContext)
        goal.setValue("Trip", forKey: "name")
        goal.setValue(household, forKey: "household")
        try oldContext.save()
        for store in coordinator.persistentStores { try coordinator.remove(store) }

        #expect(try StoreMigrator.migrateIfNeeded(storeAt: url))
        let controller = PersistenceController(storeURL: url)
        let context = controller.viewContext
        let places = try context.fetch(NSFetchRequest<Place>(entityName: "Place"))
        #expect(places.first?.name == "Rewe")
        let goals = try context.fetch(NSFetchRequest<SavingsGoal>(entityName: "SavingsGoal"))
        #expect(goals.first?.targetMonths == 0)
        #expect(try context.fetch(NSFetchRequest<RecurringRule>(entityName: "RecurringRule")).isEmpty)

        let storeCoordinator = controller.container.persistentStoreCoordinator
        for store in storeCoordinator.persistentStores { try storeCoordinator.remove(store) }
    }
}

@Suite("Categories")
@MainActor
struct CategoryTests {
    @Test func createsSubcategoryWithParentColorAndOrder() {
        let f = Fixture()
        let food = f.category("Food")
        let sub = CategoryStore.create(name: "  Bakery ", kind: .expense, icon: "birthday.cake.fill", colorName: "blue",
                                       parent: food, household: f.household, context: f.context)
        #expect(sub.name == "Bakery")
        #expect(sub.colorName == food.colorName)
        #expect(food.childList.last == sub)
    }

    @Test func movesSubcategoryToAnotherCategory() {
        let f = Fixture()
        let coffee = f.category("Coffee & snacks")
        let fun = f.category("Fun")
        f.entry(4, category: "Coffee & snacks")
        CategoryStore.move(coffee, to: fun, context: f.context)
        #expect(coffee.parent == fun)
        #expect(coffee.colorName == fun.colorName)
        #expect(CategoryStore.transactionCount(fun) == 1)
    }

    @Test func deletingMovesTransactionsFirst() {
        let f = Fixture()
        let food = f.category("Food")
        let groceries = f.category("Groceries")
        let entry = f.entry(30, category: "Restaurants")
        let target = f.category("Going out")
        #expect(!CategoryStore.reassignTargets(for: food).contains(groceries))
        CategoryStore.delete(food, movingTransactionsTo: target, context: f.context)
        #expect(entry.category == target)
        #expect(groceries.isDeleted || groceries.managedObjectContext == nil)
        #expect(!f.household.topCategories(.expense).contains { $0.name == "Food" })
    }

    @Test func hiddenCategoriesLeavePickersButKeepHistory() {
        let f = Fixture()
        let coffee = f.category("Coffee & snacks")
        f.entry(5, category: "Coffee & snacks")
        CategoryStore.setHidden(true, coffee, context: f.context)
        #expect(!f.household.pickableCategories([.expense]).contains(coffee))
        let snapshot = MonthSnapshot.build(for: MonthKey(date: .now), household: f.household, context: f.context)
        #expect(snapshot.summary.expenseSpent == 5)
    }

    @Test func reorderSavesSortOrder() {
        let f = Fixture()
        var tops = f.household.topCategories(.expense)
        let first = tops.removeFirst()
        tops.append(first)
        CategoryStore.applyOrder(tops, context: f.context)
        #expect(f.household.topCategories(.expense).last == first)
    }
}

@Suite("Places")
@MainActor
struct PlaceTests {
    @Test func matchesNamesIgnoringCase() {
        let f = Fixture()
        let a = PlaceStore.findOrCreate(named: "Rewe", in: f.household, context: f.context)
        let b = PlaceStore.findOrCreate(named: " rewe ", in: f.household, context: f.context)
        #expect(a == b)
        #expect(PlaceStore.findOrCreate(named: "   ", in: f.household, context: f.context) == nil)
    }

    @Test func remembersUsualCategory() {
        let f = Fixture()
        f.entry(20, place: "Rewe", category: "Restaurants", date: .now.addingTimeInterval(-86_400))
        f.entry(40, place: "Rewe", category: "Groceries")
        let rewe = try! #require(PlaceStore.find(named: "Rewe", in: f.household, context: f.context))
        #expect(PlaceStore.usualCategory(for: rewe, kind: .expense)?.name == "Groceries")
        #expect(PlaceStore.usualCategory(for: rewe, kind: .income) == nil)
    }

    @Test func totalsPerPlace() {
        let f = Fixture()
        f.entry(20, place: "Rewe", category: "Groceries")
        f.entry(40, place: "Rewe", category: "Groceries")
        f.entry(5, place: "Rewe", category: "Refunds", kind: .income)
        let rewe = try! #require(PlaceStore.find(named: "Rewe", in: f.household, context: f.context))
        let stats = PlaceStore.stats(for: rewe, period: .month)
        #expect(stats.total == 55)
        #expect(stats.visits == 3)
    }

    @Test func renameCollisionOffersMerge() {
        let f = Fixture()
        f.entry(10, place: "REWE City", category: "Groceries")
        f.entry(20, place: "Rewe", category: "Groceries")
        let city = try! #require(PlaceStore.find(named: "REWE City", in: f.household, context: f.context))
        let rewe = try! #require(PlaceStore.find(named: "Rewe", in: f.household, context: f.context))
        #expect(PlaceStore.rename(city, to: "rewe", context: f.context) == rewe)
        PlaceStore.merge(city, into: rewe, context: f.context)
        #expect(rewe.entryList.count == 2)
        #expect(PlaceStore.all(in: f.household, context: f.context).count == 1)
    }

    @Test func renameUpdatesEntries() {
        let f = Fixture()
        let entry = f.entry(10, place: "Edka", category: "Groceries")
        let place = try! #require(entry.place)
        #expect(PlaceStore.rename(place, to: "Edeka", context: f.context) == nil)
        #expect(entry.title == "Edeka")
        #expect(entry.payee == "Edeka")
    }
}

@Suite("Budget summary")
@MainActor
struct SummaryTests {
    @Test func noBudgetsIsCalm() {
        let f = Fixture()
        f.entry(80, category: "Groceries")
        let snapshot = MonthSnapshot.build(for: MonthKey(date: .now), household: f.household, context: f.context)
        #expect(snapshot.summary.health == .calm)
        #expect(snapshot.summary.headlineTitle == "Spent this month")
        #expect(snapshot.summary.headline == 80)
    }
}

@Suite("Budgets")
@MainActor
struct BudgetTests {
    let month = MonthKey(date: .now)

    @Test func setCopyAndMove() {
        let f = Fixture()
        let groceries = f.category("Groceries")
        let dining = f.category("Restaurants")
        BudgetStore.setBudget(400, rollsOver: false, for: groceries, month: month.previous, context: f.context)
        BudgetStore.setBudget(150, rollsOver: true, for: dining, month: month.previous, context: f.context)
        #expect(BudgetStore.copyPreviousMonth(into: month, household: f.household, context: f.context) == 2)
        #expect(BudgetStore.copyPreviousMonth(into: month, household: f.household, context: f.context) == 0)
        #expect(BudgetStore.budget(for: dining, month: month, context: f.context)?.rollsOver == true)

        BudgetStore.move(50, from: groceries, to: dining, month: month, context: f.context)
        #expect(BudgetStore.budget(for: groceries, month: month, context: f.context)?.value == 350)
        #expect(BudgetStore.budget(for: dining, month: month, context: f.context)?.value == 200)

        BudgetStore.setBudget(0, rollsOver: false, for: groceries, month: month, context: f.context)
        #expect(BudgetStore.budget(for: groceries, month: month, context: f.context) == nil)
    }

    @Test func rolloverCarriesIntoThisMonth() {
        let f = Fixture()
        let dining = f.category("Restaurants")
        BudgetStore.setBudget(150, rollsOver: true, for: dining, month: month.previous, context: f.context)
        BudgetStore.setBudget(150, rollsOver: true, for: dining, month: month, context: f.context)
        f.entry(100, category: "Restaurants", date: month.previous.firstDay().addingTimeInterval(86_400 * 3))
        let snapshot = MonthSnapshot.build(for: month, household: f.household, context: f.context)
        let line = snapshot.lines[dining.objectID]
        #expect(line?.carryover == 50)
        #expect(line?.available == 200)
    }

    @Test func everyEuroCarriesUnassignedIncome() {
        let f = Fixture()
        f.household.budgetMode = .everyDollar
        f.entry(3000, category: "Salary", kind: .income, date: month.previous.firstDay().addingTimeInterval(3600))
        BudgetStore.setBudget(2500, rollsOver: false, for: f.category("Rent"), month: month.previous, context: f.context)
        BudgetStore.setBudget(300, rollsOver: false, for: f.category("Groceries"), month: month, context: f.context)
        let snapshot = MonthSnapshot.build(for: month, household: f.household, context: f.context)
        #expect(snapshot.summary.headline == 200) // 3000 - 2500 carried in, 300 assigned this month, no income yet
    }

    @Test func averagesFromHistory() {
        let f = Fixture()
        f.entry(90, category: "Groceries", date: month.adding(months: -1).firstDay().addingTimeInterval(3600))
        f.entry(120, category: "Groceries", date: month.adding(months: -2).firstDay().addingTimeInterval(3600))
        #expect(BudgetStore.fillWithAverages(month, household: f.household, context: f.context) == 1)
        #expect(BudgetStore.budget(for: f.category("Groceries"), month: month, context: f.context)?.value == 70)
    }
}

@Suite("Recurring")
@MainActor
struct RecurringTests {
    private func rule(_ f: Fixture, start: Date, autoPost: Bool, cadence: Cadence = .weekly) -> RecurringRule {
        let rule = RecurringRule(context: f.context)
        rule.name = "Cleaning"
        rule.kind = .expense
        rule.amount = Decimal(45).number
        rule.cadence = cadence
        rule.interval = 1
        rule.startDate = start
        rule.autoPost = autoPost
        rule.category = f.category("Household")
        rule.household = f.household
        try? f.context.save()
        return rule
    }

    @Test func postsDueOccurrencesOnce() {
        let f = Fixture()
        let now = Date.now
        let created = rule(f, start: now.addingTimeInterval(-15 * 86_400), autoPost: true)
        #expect(RecurringStore.postDue(in: f.household, context: f.context, now: now) == 3) // -15, -8, -1 days
        #expect(RecurringStore.postDue(in: f.household, context: f.context, now: now) == 0)
        #expect((created.entries as? Set<LedgerEntry>)?.count == 3)
        #expect(created.nextDate.map { $0 > now } == true)
    }

    @Test func confirmationFlow() {
        let f = Fixture()
        let now = Date.now
        _ = rule(f, start: now.addingTimeInterval(-86_400), autoPost: false)
        RecurringStore.postDue(in: f.household, context: f.context, now: now)
        let pending = RecurringStore.pending(in: f.household, context: f.context)
        #expect(pending.count == 1)
        let before = MonthSnapshot.build(for: MonthKey(date: now), household: f.household, context: f.context)
        #expect(before.summary.expenseSpent == 0)
        RecurringStore.confirm(pending[0], context: f.context)
        #expect(RecurringStore.pending(in: f.household, context: f.context).isEmpty)
    }

    @Test func upcomingCountsFutureOccurrencesThisMonth() {
        let f = Fixture()
        let calendar = Calendar.current
        let month = MonthKey(date: .now)
        let first = month.firstDay()
        let now = calendar.date(byAdding: .hour, value: 12, to: first)! // the 1st, midday
        let monthly = rule(f, start: calendar.date(byAdding: .day, value: 14, to: first)!, autoPost: true, cadence: .monthly)
        monthly.amount = Decimal(100).number
        #expect(RecurringStore.upcomingExpenses(in: month, household: f.household, context: f.context, now: now) == 100)
    }
}
