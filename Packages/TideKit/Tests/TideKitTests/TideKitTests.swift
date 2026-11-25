import Foundation
import Testing
@testable import TideKit

@Suite struct MoneyTests {
    @Test func addsAndRounds() {
        let total = Money(Decimal(string: "10.105")!, .eur) + Money(Decimal(string: "0.10")!, .eur)
        #expect(total.rounded.amount == Decimal(string: "10.21"))
    }

    @Test func fractionDigits() {
        #expect(CurrencyCode.eur.fractionDigits == 2)
        #expect(CurrencyCode("jpy").fractionDigits == 0)
        #expect(CurrencyCode("KWD").fractionDigits == 3)
        #expect(CurrencyCode("gbp") == .gbp)
    }

    @Test func formatsInEuro() {
        let text = Money(Decimal(string: "1240.5")!, .eur).formatted(locale: Locale(identifier: "en_IE"))
        #expect(text == "€1,240.50")
    }
}

@Suite struct ExchangeRateTests {
    @Test func impliedRateFromBankCharge() throws {
        let rate = try #require(ExchangeRate.implied(original: Money(Decimal(string: "42.10")!, .gbp),
                                                     converted: Money(Decimal(string: "49.38")!, .eur)))
        #expect(rate.from == .gbp)
        #expect(rate.to == .eur)
        #expect(rate.convert(Money(Decimal(string: "42.10")!, .gbp)).amount == Decimal(string: "49.38"))
    }

    @Test func convertsToZeroDecimalCurrency() {
        let rate = ExchangeRate(from: .eur, to: "JPY", rate: Decimal(string: "162.37")!)
        #expect(rate.convert(Money(10, .eur)).amount == 1624)
    }

    @Test func rejectsZeroAmounts() {
        #expect(ExchangeRate.implied(original: .zero(.gbp), converted: Money(5, .eur)) == nil)
    }
}

@Suite struct MonthKeyTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    @Test func idRoundTrip() {
        let key = MonthKey(year: 2026, month: 11)
        #expect(key.id == "2026-11")
        #expect(MonthKey(id: "2026-11") == key)
        #expect(MonthKey(id: "2026-13") == nil)
    }

    @Test func wrapsYears() {
        #expect(MonthKey(year: 2026, month: 12).next == MonthKey(year: 2027, month: 1))
        #expect(MonthKey(year: 2026, month: 1).previous == MonthKey(year: 2025, month: 12))
        #expect(MonthKey(year: 2026, month: 3).adding(months: -15) == MonthKey(year: 2024, month: 12))
    }

    @Test func daysRemainingAndProgress() {
        let key = MonthKey(year: 2026, month: 11)
        let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 12))!
        #expect(key.numberOfDays(calendar: calendar) == 30)
        #expect(key.daysRemaining(from: date, calendar: calendar) == 7)
        #expect(abs(key.progress(at: date, calendar: calendar) - 23.5 / 30) < 0.001)
    }
}

@Suite struct BudgetEngineTests {
    let lines = [
        CategoryBudgetLine(kind: .expense, budgeted: 400, actual: 210),
        CategoryBudgetLine(kind: .expense, budgeted: 150, actual: 90),
        CategoryBudgetLine(kind: .savings, budgeted: 300, actual: 300),
        CategoryBudgetLine(kind: .debt, budgeted: 200, actual: 200),
    ]

    @Test func limitsModeSafeToSpend() {
        let summary = BudgetEngine.summarize(mode: .limits, lines: lines, incomeReceived: 3000,
                                             upcomingBills: 50, monthProgress: 0.5, daysRemaining: 10)
        #expect(summary.headline == 200) // 550 budget - 300 spent - 50 bills
        #expect(summary.dailyAllowance == 20)
        #expect(summary.totalTransferred == 500)
        #expect(summary.health == .calm)
        #expect(summary.headlineTitle == "Safe to spend")
    }

    @Test func limitsModeTurnsAmberWhenSpendingAheadOfTime() {
        let summary = BudgetEngine.summarize(mode: .limits, lines: lines, incomeReceived: 0,
                                             monthProgress: 0.3, daysRemaining: 20)
        #expect(summary.health == .watch) // 55% spent, 30% of month gone
    }

    @Test func everyDollarModeReadyToAssign() {
        let summary = BudgetEngine.summarize(mode: .everyDollar, lines: lines, incomeReceived: 1000,
                                             unassignedCarryIn: 100, monthProgress: 0.5, daysRemaining: 10)
        #expect(summary.headline == 50) // 1100 - 1050 assigned
        #expect(summary.headlineTitle == "Ready to assign")
        #expect(summary.dailyAllowance == nil)
    }

    @Test func overAssignedIsCoral() {
        let summary = BudgetEngine.summarize(mode: .everyDollar, lines: lines, incomeReceived: 500,
                                             monthProgress: 0.5, daysRemaining: 10)
        #expect(summary.headline == -550)
        #expect(summary.health == .over)
        #expect(summary.headlineTitle == "Over-assigned")
    }

    @Test func lineStatus() {
        #expect(CategoryBudgetLine(kind: .expense, budgeted: 100, actual: 50).status == .onTrack)
        #expect(CategoryBudgetLine(kind: .expense, budgeted: 100, actual: 90).status == .nearLimit)
        #expect(CategoryBudgetLine(kind: .expense, budgeted: 100, actual: 101).status == .over)
        #expect(CategoryBudgetLine(kind: .expense, budgeted: 100, actual: 110, carryover: 20).status == .nearLimit)
        #expect(CategoryBudgetLine(kind: .expense, budgeted: 0, actual: 0).progress == 0)
        #expect(CategoryBudgetLine(kind: .expense, budgeted: 0, actual: 25).status == .unbudgeted)
        #expect(CategoryBudgetLine(kind: .expense, budgeted: 0, actual: 25).progress == 0)
    }

    @Test func unbudgetedSpendingDoesNotTurnAmber() {
        let lines = [
            CategoryBudgetLine(kind: .expense, budgeted: 400, actual: 100),
            CategoryBudgetLine(kind: .expense, budgeted: 0, actual: 60),
        ]
        let summary = BudgetEngine.summarize(mode: .everyDollar, lines: lines, incomeReceived: 1000,
                                             monthProgress: 0.5, daysRemaining: 15)
        #expect(summary.health == .calm)
    }

    @Test func limitsWithoutBudgetsShowsSpending() {
        let lines = [CategoryBudgetLine(kind: .expense, budgeted: 0, actual: 42)]
        let summary = BudgetEngine.summarize(mode: .limits, lines: lines, incomeReceived: 0,
                                             monthProgress: 0.8, daysRemaining: 5)
        #expect(summary.headline == 42)
        #expect(summary.health == .calm)
        #expect(summary.hasExpenseBudget == false)
        #expect(summary.headlineTitle == "Spent this month")
        #expect(summary.dailyAllowance == nil)
    }
}

@Suite struct AmountInputTests {
    @Test func typesAnAmount() {
        var input = AmountInput(currency: .eur)
        for key: AmountInput.Key in [.digit(4), .digit(2), .separator, .digit(1), .digit(0), .digit(9)] {
            input.press(key)
        }
        #expect(input.value == Decimal(string: "42.10"))
        #expect(input.displayText(locale: Locale(identifier: "de_DE")) == "42,10")
    }

    @Test func leadingZerosAndDelete() {
        var input = AmountInput(currency: .eur)
        input.press(.digit(0))
        input.press(.digit(0))
        input.press(.digit(7))
        #expect(input.displayText(locale: Locale(identifier: "en_US")) == "7")
        input.press(.separator)
        input.press(.delete)
        input.press(.delete)
        #expect(input.isEmpty)
    }

    @Test func noDecimalsForYen() {
        var input = AmountInput(currency: "JPY")
        input.press(.digit(5))
        input.press(.separator)
        input.press(.digit(5))
        #expect(input.value == 55)
    }

    @Test func groupsThousands() {
        var input = AmountInput(currency: .eur)
        for digit in [1, 2, 4, 0, 0, 0, 0] { input.press(.digit(digit)) }
        #expect(input.displayText(locale: Locale(identifier: "en_US")) == "1,240,000")
    }

    @Test func startsFromExistingAmount() {
        let input = AmountInput(value: Decimal(string: "42.1")!, currency: .eur)
        #expect(input.value == Decimal(string: "42.10"))
        #expect(input.displayText(locale: Locale(identifier: "en_US")) == "42.10")
        #expect(AmountInput(value: 1250, currency: .eur).displayText(locale: Locale(identifier: "en_US")) == "1,250")
        #expect(AmountInput(value: 0, currency: .eur).isEmpty)
        #expect(AmountInput(value: Decimal(string: "980")!, currency: "JPY").value == 980)
    }

    @Test func switchingToYenTrimsCents() {
        var input = AmountInput(currency: .eur)
        for key: AmountInput.Key in [.digit(3), .separator, .digit(5)] { input.press(key) }
        input.setMaxFractionDigits(0)
        #expect(input.value == 3)
    }
}

@Suite struct PlaceTests {
    @Test func cleansAndMatchesNames() {
        #expect(PlaceName.clean("  Rewe   City ") == "Rewe City")
        #expect(PlaceName.key("REWE") == PlaceName.key(" rewe"))
        #expect(PlaceName.key("Réwe") == PlaceName.key("rewe"))
        #expect(PlaceName.initial(" blue door") == "B")
        #expect(PlaceName.initial("") == "?")
    }

    @Test func stableColor() {
        let a = PlaceName.colorIndex("Rewe", paletteSize: 12)
        #expect(a == PlaceName.colorIndex("REWE ", paletteSize: 12))
        #expect((0..<12).contains(a))
    }

    @Test func suggestionsRankPrefixFirst() {
        let names = ["Edeka", "Rewe City", "Brewery", "Rewe", "Café Rewe"]
        #expect(PlaceName.suggestions(for: "rew", in: names) == ["Rewe City", "Rewe", "Café Rewe", "Brewery"])
        #expect(PlaceName.suggestions(for: "", in: names, limit: 2) == ["Edeka", "Rewe City"])
    }

    @Test func statsAndMonthly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func day(_ m: Int, _ d: Int) -> Date { calendar.date(from: DateComponents(year: 2026, month: m, day: d))! }
        let visits = [
            PlaceStats.Visit(date: day(10, 3), amount: 40),
            PlaceStats.Visit(date: day(11, 2), amount: 50),
            PlaceStats.Visit(date: day(11, 20), amount: 30),
        ]
        let all = PlaceStats.compute(visits)
        #expect(all.total == 120)
        #expect(all.visits == 3)
        #expect(all.average == 40)
        #expect(all.lastVisit == day(11, 20))

        let november = PlaceStats.compute(visits, in: MonthKey(year: 2026, month: 11).interval(calendar: calendar))
        #expect(november.total == 80)
        #expect(november.visits == 2)

        let monthly = PlaceStats.monthly(visits, last: MonthKey(year: 2026, month: 11), count: 3, calendar: calendar)
        #expect(monthly.map(\.total) == [0, 40, 80])
        #expect(monthly.first?.month == MonthKey(year: 2026, month: 9))
    }
}

@Suite struct RecurrenceTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 9))!
    }

    @Test func monthlyOnThe31stClampsToMonthEnd() {
        let rent = Recurrence(cadence: .monthly, start: day(2026, 1, 31))
        let dates = rent.occurrences(from: day(2026, 1, 1), through: day(2026, 4, 30), calendar: calendar)
        #expect(dates == [day(2026, 1, 31), day(2026, 2, 28), day(2026, 3, 31), day(2026, 4, 30)])
    }

    @Test func everyTwoWeeks() {
        let rule = Recurrence(cadence: .weekly, interval: 2, start: day(2026, 11, 2))
        #expect(rule.next(after: day(2026, 11, 2), calendar: calendar) == day(2026, 11, 16))
        #expect(rule.occurrences(from: day(2026, 11, 10), through: day(2026, 12, 1), calendar: calendar).count == 2)
    }

    @Test func quarterlyAndYearlyWithEnd() {
        let quarterly = Recurrence(cadence: .monthly, interval: 3, start: day(2026, 1, 15))
        #expect(quarterly.next(after: day(2026, 2, 1), calendar: calendar) == day(2026, 4, 15))
        let yearly = Recurrence(cadence: .yearly, start: day(2024, 2, 29), end: day(2026, 12, 31))
        #expect(yearly.occurrences(from: day(2024, 1, 1), through: day(2030, 1, 1), calendar: calendar)
                == [day(2024, 2, 29), day(2025, 2, 28), day(2026, 2, 28)])
        #expect(yearly.next(after: day(2026, 3, 1), calendar: calendar) == nil)
    }
}

@Suite struct BudgetingTests {
    @Test func rolloverCarriesLeftoverAndOverspending() {
        #expect(Rollover.carryover(after: []) == 0)
        #expect(Rollover.carryover(after: [MonthFlow(budgeted: 100, actual: 70, rollsOver: true)]) == 30)
        let chain = [
            MonthFlow(budgeted: 100, actual: 70, rollsOver: true),  // +30
            MonthFlow(budgeted: 100, actual: 150, rollsOver: true), // 30 + 100 - 150 = -20
        ]
        #expect(Rollover.carryover(after: chain) == -20)
        let reset = chain + [MonthFlow(budgeted: 100, actual: 10, rollsOver: false)]
        #expect(Rollover.carryover(after: reset) == 0)
    }

    @Test func unassignedCarry() {
        #expect(EveryEuro.unassignedCarryIn(incomeBefore: 6000, assignedBefore: 5800) == 200)
    }

    @Test func averageSuggestion() {
        #expect(BudgetSuggestion.average([100, 0, 51]) == 51)
        #expect(BudgetSuggestion.average([]) == 0)
    }

    @Test func goalPace() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let deadline = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!
        let mid = calendar.date(from: DateComponents(year: 2026, month: 7, day: 2))!
        let goal = GoalProgress(target: 1200, saved: 300, start: start, deadline: deadline)
        #expect(goal.pace(at: mid) == .behind)
        #expect(goal.monthsLeft(from: mid, calendar: calendar) == 6)
        #expect(goal.monthlyNeeded(from: mid, calendar: calendar) == 150)
        #expect(GoalProgress(target: 1200, saved: 700, start: start, deadline: deadline).pace(at: mid) == .ahead)
        #expect(GoalProgress(target: 100, saved: 100, start: start, deadline: nil).pace(at: mid) == .done)
    }
}

@Suite struct ECBRatesTests {
    let xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01" xmlns="http://www.ecb.int/vocabulary/2002-08-01/eurofxref">
      <gesmes:subject>Reference rates</gesmes:subject>
      <Cube>
        <Cube time="2026-11-24">
          <Cube currency="USD" rate="1.1612"/>
          <Cube currency="GBP" rate="0.8526"/>
        </Cube>
        <Cube time="2026-11-23">
          <Cube currency="USD" rate="1.1580"/>
          <Cube currency="GBP" rate="0.8500"/>
        </Cube>
      </Cube>
    </gesmes:Envelope>
    """

    @Test func parsesAndConverts() throws {
        let rates = try #require(ECBRates.parse(Data(xml.utf8)))
        #expect(rates.days.count == 2)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let monday = utc.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 20))!
        let gbpToEur = try #require(rates.rate(from: .gbp, to: .eur, on: monday))
        #expect(gbpToEur.convert(Money(Decimal(string: "42.50")!, .gbp)).amount == 50)
        let later = utc.date(from: DateComponents(year: 2026, month: 11, day: 30))!
        #expect(rates.rate(from: .eur, to: .usd, on: later)?.rate == Decimal(string: "1.1612"))
        #expect(rates.rate(from: "XYZ", to: .eur, on: later) == nil)
        #expect(ECBRates.parse(Data("nonsense".utf8)) == nil)
    }
}
