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

    @Test func switchingToYenTrimsCents() {
        var input = AmountInput(currency: .eur)
        for key: AmountInput.Key in [.digit(3), .separator, .digit(5)] { input.press(key) }
        input.setMaxFractionDigits(0)
        #expect(input.value == 3)
    }
}
