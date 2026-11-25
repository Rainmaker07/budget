import CoreData
import TideKit

/// A realistic month for Alex & Sam, used by previews, screenshots and the
/// `-demo YES` launch argument. Never written to the real store.
enum DemoData {
    @MainActor
    static func populate(_ context: NSManagedObjectContext, now: Date = .now, mode: BudgetMode = .limits) {
        let calendar = Calendar.current
        let month = MonthKey(date: now, calendar: calendar)

        let household = Household(context: context)
        household.name = "Alex & Sam"
        household.baseCurrency = "EUR"
        household.budgetMode = mode

        let alex = Member(context: context)
        alex.name = "Alex"
        alex.colorName = "blue"
        alex.sortOrder = 0
        alex.household = household

        let sam = Member(context: context)
        sam.name = "Sam"
        sam.colorName = "pink"
        sam.sortOrder = 1
        sam.household = household

        let categories = StarterCategories.install(in: household, context: context)

        func account(_ name: String, _ kind: AccountKind, _ icon: String, _ color: String, balance: Decimal,
                     category: String? = nil, rate: Decimal = 0, order: Int16) -> Account {
            let account = Account(context: context)
            account.name = name
            account.kindRaw = kind.rawValue
            account.icon = icon
            account.colorName = color
            account.openingBalance = balance.number
            account.interestRate = rate.number
            account.sortOrder = order
            account.household = household
            account.category = category.flatMap { categories[$0] }
            return account
        }

        let joint = account("Joint account", .current, "building.columns.fill", "blue", balance: 2840, order: 0)
        _ = account("Alex's card", .creditCard, "creditcard.fill", "indigo", balance: -320,
                    category: "Credit card", rate: 18.9, order: 1)
        let savings = account("Savings", .savings, "banknote.fill", "teal", balance: 9450,
                              category: "Emergency fund", rate: 2.5, order: 2)
        _ = account("ETF portfolio", .investment, "chart.pie.fill", "green", balance: 18_200,
                    category: "ETF portfolio", order: 3)
        _ = account("Car loan", .loan, "car.fill", "red", balance: -8_600, category: "Car loan", rate: 5.4, order: 4)

        // Monthly budgets.
        let budgets: [String: Decimal] = [
            "Rent": 1250, "Utilities": 140, "Internet & phone": 60, "Insurance": 90,
            "Groceries": 520, "Restaurants": 200, "Coffee & snacks": 45,
            "Fuel & charging": 120, "Public transport": 60,
            "Pharmacy": 30, "Fitness": 50,
            "Clothes": 100, "Household": 60,
            "Going out": 90, "Hobbies": 60, "Subscriptions": 45,
            "Holiday spending": 150,
            "Personal care": 40, "Gifts given": 50,
            "Emergency fund": 300, "Travel fund": 250,
            "ETF portfolio": 400, "Pension": 200,
            "Car loan": 280, "Credit card": 150,
        ]
        for (name, amount) in budgets {
            guard let category = categories[name] else { continue }
            let budget = MonthlyBudget(context: context)
            budget.monthID = month.id
            budget.amount = amount.number
            budget.category = category
            budget.household = household
        }

        // Transactions: (day, kind, category, payee, amount, payer, foreign).
        struct Row {
            let day: Int, kind: EntryKind, category: String, payee: String, amount: String, payer: Member
            var foreign: (amount: String, currency: String)?
        }
        func r(_ day: Int, _ kind: EntryKind, _ category: String, _ payee: String, _ amount: String,
               _ payer: Member, _ foreign: (amount: String, currency: String)? = nil) -> Row {
            Row(day: day, kind: kind, category: category, payee: payee, amount: amount, payer: payer, foreign: foreign)
        }
        let rows: [Row] = [
            r(1, .income, "Salary", "Studio Nord GmbH", "3420.00", alex),
            r(1, .income, "Salary", "City Hospital", "2980.00", sam),
            r(1, .expense, "Rent", "Rent – Lindenstraße", "1250.00", alex),
            r(1, .transfer, "Emergency fund", "Savings", "300.00", alex),
            r(1, .transfer, "ETF portfolio", "Monthly ETF plan", "400.00", sam),
            r(2, .expense, "Subscriptions", "Music streaming", "16.99", sam),
            r(2, .expense, "Groceries", "Rewe", "86.40", sam),
            r(3, .expense, "Coffee & snacks", "Café Fleur", "7.80", alex),
            r(4, .expense, "Fitness", "Climbing gym", "49.00", alex),
            r(5, .transfer, "Car loan", "Car loan", "280.00", alex),
            r(5, .expense, "Utilities", "Stadtwerke", "138.00", alex),
            r(6, .expense, "Restaurants", "Trattoria Roma", "64.50", sam),
            r(7, .expense, "Fuel & charging", "Aral", "58.20", alex),
            r(8, .expense, "Groceries", "Edeka", "112.35", alex),
            r(9, .expense, "Internet & phone", "Telekom", "59.95", sam),
            r(10, .expense, "Clothes", "COS", "89.00", sam),
            r(11, .expense, "Going out", "Cinema", "28.00", alex),
            r(12, .expense, "Restaurants", "Dishoom London", "49.38", alex, ("42.10", "GBP")),
            r(12, .expense, "Holiday spending", "Borough Market", "31.65", sam, ("26.98", "GBP")),
            r(14, .expense, "Groceries", "Rewe", "94.10", sam),
            r(15, .income, "Freelance", "Logo project", "450.00", alex),
            r(15, .transfer, "Travel fund", "Japan trip", "250.00", sam),
            r(16, .expense, "Pharmacy", "Apotheke", "18.40", sam),
            r(17, .expense, "Coffee & snacks", "Bakery", "5.60", sam),
            r(18, .expense, "Household", "IKEA", "47.90", alex),
            r(19, .expense, "Restaurants", "Sushi bar", "72.00", alex),
            r(20, .expense, "Groceries", "Markt", "38.75", alex),
            r(21, .expense, "Public transport", "Monthly pass", "58.00", sam),
            r(22, .expense, "Going out", "Concert tickets", "64.00", sam),
            r(22, .expense, "Insurance", "Liability insurance", "88.00", alex),
            r(23, .expense, "Groceries", "Rewe", "102.60", sam),
            r(24, .expense, "Coffee & snacks", "Blue Door Coffee", "6.50", alex),
            r(24, .expense, "Gifts given", "Birthday gift", "35.00", sam),
            r(25, .expense, "Restaurants", "Ramen", "41.00", sam),
            r(27, .expense, "Groceries", "Edeka", "88.20", alex),
        ]

        let today = calendar.component(.day, from: now)
        let isCurrentMonth = MonthKey(date: now, calendar: calendar) == month
        for (index, row) in rows.enumerated() where !isCurrentMonth || row.day <= today {
            guard let category = categories[row.category],
                  let date = calendar.date(from: DateComponents(year: month.year, month: month.month,
                                                                day: row.day, hour: 9 + index % 10, minute: (index * 7) % 60))
            else { continue }
            let entry = LedgerEntry(context: context)
            entry.kind = row.kind
            entry.date = date
            entry.payee = row.payee
            entry.category = category
            entry.account = joint
            entry.payer = row.payer
            entry.household = household
            let base = Decimal(string: row.amount)!
            entry.baseAmount = base.number
            if let foreign = row.foreign {
                entry.originalAmount = Decimal(string: foreign.amount)!.number
                entry.originalCurrency = foreign.currency
            } else {
                entry.originalAmount = base.number
                entry.originalCurrency = "EUR"
            }
            if row.kind == .transfer, category.kind == .savings {
                entry.toAccount = savings
            }
        }

        // Places: link entries to Place records, and give a few their own logos.
        PlaceStore.backfill(household, context: context)
        for (name, emoji) in [("Blue Door Coffee", "☕️"), ("Café Fleur", "🥐"), ("Climbing gym", "🧗"), ("Japan trip", "🗾")] {
            PlaceStore.find(named: name, in: household, context: context)?.emoji = emoji
        }
        PlaceStore.find(named: "Rewe", in: household, context: context)?.colorName = "red"
        PlaceStore.find(named: "Edeka", in: household, context: context)?.colorName = "yellow"

        // Recurring items: monthly ones already posted this month start next
        // month; a weekly one waits for confirmation on Home.
        func recurring(_ name: String, _ kind: EntryKind, _ amount: Decimal, category: String, place: String?,
                       cadence: Cadence = .monthly, day: Int = 1, autoPost: Bool = true, payer: Member,
                       start: Date? = nil) {
            let rule = RecurringRule(context: context)
            rule.name = name
            rule.kind = kind
            rule.amount = amount.number
            rule.currencyCode = "EUR"
            rule.cadence = cadence
            rule.interval = 1
            rule.startDate = start ?? calendar.date(from: DateComponents(year: month.year, month: month.month, day: day, hour: 9))
            rule.autoPost = autoPost
            rule.category = categories[category]
            rule.place = place.flatMap { PlaceStore.findOrCreate(named: $0, in: household, context: context) }
            rule.payer = payer
            rule.account = joint
            rule.household = household
            if start == nil, let recurrence = rule.recurrence {
                rule.nextDate = recurrence.next(after: month.next.firstDay(calendar: calendar).addingTimeInterval(-1))
            }
        }
        recurring("Rent", .expense, 1250, category: "Rent", place: "Rent – Lindenstraße", payer: alex)
        recurring("Alex's salary", .income, 3420, category: "Salary", place: "Studio Nord GmbH", payer: alex)
        recurring("Sam's salary", .income, 2980, category: "Salary", place: "City Hospital", payer: sam)
        recurring("ETF savings plan", .transfer, 400, category: "ETF portfolio", place: "Monthly ETF plan", payer: sam)
        recurring("Music streaming", .expense, Decimal(string: "16.99")!, category: "Subscriptions", place: "Music streaming", day: 2, payer: sam)
        recurring("Electricity", .expense, 138, category: "Utilities", place: "Stadtwerke", day: 5, autoPost: false, payer: alex)
        recurring("Cleaning help", .expense, 45, category: "Household", place: "Cleaning help", cadence: .weekly,
                  autoPost: false, payer: sam, start: calendar.date(byAdding: .day, value: -3, to: now))

        // Goals.
        let japan = SavingsGoal(context: context)
        japan.name = "Japan trip"
        japan.icon = "airplane"
        japan.colorName = "pink"
        japan.targetAmount = Decimal(6000).number
        japan.savedAmount = Decimal(2350).number
        japan.targetDate = calendar.date(byAdding: .month, value: 10, to: month.firstDay(calendar: calendar))
        japan.category = categories["Travel fund"]
        japan.sortOrder = 0
        japan.household = household

        let emergency = SavingsGoal(context: context)
        emergency.name = "Emergency fund"
        emergency.icon = "lifepreserver.fill"
        emergency.colorName = "teal"
        emergency.targetAmount = Decimal(12_000).number
        emergency.savedAmount = Decimal(9450).number
        emergency.targetDate = calendar.date(byAdding: .month, value: 8, to: month.firstDay(calendar: calendar))
        emergency.category = categories["Emergency fund"]
        emergency.account = savings
        emergency.sortOrder = 1
        emergency.household = household

        let car = SavingsGoal(context: context)
        car.name = "Car paid off"
        car.kindRaw = "payOff"
        car.icon = "car.fill"
        car.colorName = "orange"
        car.targetAmount = Decimal(14_000).number
        car.savedAmount = Decimal(5_400).number
        car.targetDate = calendar.date(byAdding: .month, value: 30, to: month.firstDay(calendar: calendar))
        car.category = categories["Car loan"]
        car.sortOrder = 2
        car.household = household

        try? context.save()
    }
}
