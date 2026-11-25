# Tide

**Version 0.2.0** · [Changelog](CHANGELOG.md) · [Roadmap](docs/PLAN.md)

A calm, Liquid Glass budget app for couples, for iOS 27.

Track income, expenses, savings, investments and debts, budget each category
by month, and see where your money goes, place by place. Euro first, with
any currency allowed for spending abroad.

## Features

- **Home**: safe to spend (or ready to assign), recurring items to confirm,
  budget rings per category, goals, recent transactions; the background
  tints with how the month is going
- **Plan**: monthly budgets per category with suggestions, copy last month,
  3-month averages, roll-over, Every Euro assigning and moving money, goals
  with monthly targets and pace, recurring income and bills
- **Quick Add**: amount pad on tap, place with suggestions, category filled
  in from your last visit, who paid, account, note, any currency (with ECB
  exchange rate suggestions)
- **Activity**: one card per day, search, filters (type, person, category,
  account, amount), and a **Places** view with total spent per shop or vendor
- **Transaction detail & editing**: edit, duplicate, delete
- **Places**: totals, visits, 6-month chart, logos, rename and merge
- **Categories**: income, expenses, savings, investments and debts with
  subcategories; add, edit, reorder, move, hide, delete
- **Settings**: household and people, Limits or Every Euro budgeting, About

Screenshots from every CI build are on the
[`ci-screenshots`](../../tree/ci-screenshots) branch.

## Run it on your iPhone

1. Open `Tide.xcodeproj` in **Xcode 27**.
2. Select the **Tide** target → *Signing & Capabilities* → choose your
   **Team** (a free Apple ID works for installing on your own phone). If the
   bundle ID `app.tide.Tide` is taken, change it to something unique, e.g.
   `com.yourname.tide`.
3. Plug in your iPhone (or pick it over Wi-Fi), select it as the run
   destination, and press **Run**.

Updating from an older version keeps your data: Tide upgrades its database
automatically on first launch.

### Demo data

To look around with a realistic month of sample data, edit the scheme
(*Product → Scheme → Edit Scheme → Run → Arguments*) and tick the
`-demo YES` argument. Demo data lives in memory only and never touches your
real data.

## Project layout

```
Tide.xcodeproj          Xcode project (folders are synced automatically)
Tide/
  App/                  App entry, app-wide model, month snapshot, version info
  DesignSystem/         Glass components, background, palette, logos, pickers
  Features/             Home, Quick Add / editor, Activity, Places, Settings…
  Persistence/          Core Data schema (versioned, in code), migration, stores, demo data
TideTests/              App tests: migrations, categories, places, budgets, recurring
Packages/TideKit/       Pure Swift logic: money, currencies, months, budget engine, places (+ tests)
.github/workflows/      CI: tests, build, simulator screenshots, release tags
```

## CI

Every push runs on GitHub's macOS runners:

1. `swift test` for TideKit
2. builds the app and runs the app tests in an iPhone simulator
3. launches it with demo data and takes screenshots in light and dark mode
4. creates release tags listed in `.github/release-tags.txt`
