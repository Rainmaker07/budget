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

## Milestones

1. **Foundation** ✅ in progress — project, CI, data model, glass design
   system, Home, Quick Add, basic Activity
2. **Budgeting** — Plan tab: monthly budgets, both modes in full, goals,
   recurring items, category editor, Activity search & filters, edit transactions
3. **Wealth** — accounts, month-end balance check-in, net worth history,
   savings & investment trends, debt payoff planner
4. **Reports** — year overview, budget history, cash flow, money in/out
   flows, trends, ways to improve
5. **Couples** — iCloud sync, partner invite (CloudKit share), who paid,
   private categories, splits, partner notifications
6. **Apple extras** — widgets, Live Activity, Control Center, Siri / App
   Intents, Face ID lock
7. **Later** — bank import via an EU open banking provider
