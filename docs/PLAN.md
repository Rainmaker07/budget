# Tide — product plan

A native iOS 27 budget app with a heavy Apple / Liquid Glass aesthetic,
built for couples sharing one budget.

## Decisions

| Topic | Decision |
|---|---|
| Platform | Native iOS 27 only, SwiftUI, Liquid Glass APIs |
| Data | Core Data + CloudKit (`NSPersistentCloudKitContainer`): built-in sharing for couples. SwiftData can't share between iCloud users yet. |
| Install | Xcode on your Mac; CI builds and screenshots on GitHub macOS runners |
| Currency | Euro base, every account and transaction can use any currency |
| Budgeting | Both modes: **Limits** (cap per category, "safe to spend") and **Every Euro** (zero-based, "ready to assign") |
| Sharing | One household budget shared via iCloud; who paid, personal categories, splits |
| Import | Manual entry now. Bank import later via EU open banking (needs a small backend). |
| Market data | European ETFs + US stocks, ~15-minute delayed quotes (v0.3) |
| Versioning | Every release bumps the version shown in the app, CHANGELOG and README, and gets a git tag |

## Category tree

Three levels: **kind → category → subcategory**. Transactions are filed
under subcategories and roll up.

- **Income** – Salary, Side income, Other income
- **Expenses** – Home, Food, Transport, Health, Shopping, Fun, Travel, Personal, Other
- **Savings** – Emergency fund, Travel fund, Big purchases
- **Investments** – Pension, ETF portfolio
- **Debts** – Car loan, Credit card, Student loan

Savings, investment and debt categories are linked to accounts with
balances. Money moved there is a transfer, not spending.

## Feature list

- Categories for income, expenses, debts, investments and savings with subcategories
- Goals (save by a date, emergency fund, pay off a debt, net worth milestone)
- Budgets per category per month, with optional rollover
- Fast transaction input (Quick Add), multi-currency
- Monthly net worth tracking, history and trends
- Monthly and yearly budget tracking, history and trends
- Year overview
- Where money comes from / where money goes
- Trends and changes (month-over-month, year-over-year, biggest movers)
- Ways to improve (rule-based insights, on device)
- Savings trends, investment trends (contributions vs. growth)
- Debt payoff schedule (avalanche / snowball / custom, extra payment slider)
- Cash flow report

## Multi-currency

- Each transaction stores the **original amount and currency** (e.g. £42.10)
  and the **base amount** in euro (e.g. €49.38), which budgets and reports use.
- Abroad, you enter what your bank charged; Tide shows the implied rate.
- Later: European Central Bank daily reference rates as a suggestion.

## Roadmap

### ✅ v0.1.0 — Foundation
Project, CI, data model, glass design system, Home, Quick Add, basic Activity.

### ✅ v0.1.1 — Editing, places & settings
Settings; category management; transaction detail + editor; Revolut-style
transaction list; places with suggestions, auto-category, totals, logos,
rename/merge; number pad on tap; unbudgeted-spending fix; version in app.

### v0.2 — Budgeting
Plan tab with monthly budgets per category (copy last month / average,
rollover), Every Euro mode in full, goals create/edit with monthly targets,
recurring items, Activity filters by category/account/amount, ECB exchange
rate suggestions.

### v0.3 — Wealth
Accounts in any currency, month-end check-in, net worth history,
savings and investment trends, debt payoff planner (avalanche / snowball /
custom, extra payment, debt-free date, interest saved), principal/interest
split. **Investment holdings with automatic ~15-min delayed quotes** for
European ETFs (by ISIN/ticker) and US stocks (converted to EUR), gains,
allocation, contributions vs growth, sold positions with realized gains.

### v0.4 — Reports
Year overview, monthly/yearly budget history, where money comes from and
goes (flow chart), cash flow report with forecast, trends and biggest
movers, ways to improve, CSV/PDF export.

### v0.5 — Couples
iCloud sync, partner invite (CloudKit share), "who paid" from iCloud
identity, private categories, splits and who-owes-whom, notifications.
Needs a paid Apple Developer account.

### v0.6 — Apple extras
Widgets, Live Activity, Control Center, Siri / Shortcuts, Face ID lock.

### v0.7 — Tide for Mac
Native macOS app on the same code and iCloud data: sidebar, multiple
windows, sortable tables, big charts, keyboard shortcuts, menu bar quick add,
CSV import, printing.

### Later
- Automatic brand logos for places (logo service, needs an API key)
- Nearby place suggestions from your location (Apple Maps)
- Bank import via an EU open banking provider (small backend)
- Receipt scanning
- Apple Wallet import if FinanceKit comes to the EU
- iPad layout
- v1.0: polish, onboarding, TestFlight / App Store
