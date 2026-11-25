# Changelog

All notable changes to Tide. Versions follow `MAJOR.MINOR.PATCH`; the
version is shown in the app (Settings → About, and at the bottom of Home).

## 0.1.1 — Editing, places & settings

### New
- **Settings** (tap the avatars on Home): household name, people, budgeting
  style, categories, places, and About with the version number.
- **Manage categories and subcategories**: add, rename, change icon and
  color, reorder by dragging, move a subcategory to another category, hide,
  and delete. Deleting a category with transactions asks where to move them
  (or lets you hide it instead, keeping its history).
- **Edit transactions**: tap any transaction for its detail page, then Edit,
  Duplicate or Delete. Swipe in Activity for Edit and Delete. Notes are back.
- **Places**: a Place field right under the amount, with suggestions as you
  type, recent places, and the category filled in from your last visit.
- **Total spent per place**: Activity → Places lists every shop or vendor
  with total, visits and average, for this month, this year or all time.
  Each place has a page with a 6-month chart and all its transactions.
- **Rename and merge places** (e.g. "REWE" and "Rewe").
- **Place logos**: choose a photo, emoji or symbol, or use the automatic
  colored initial.
- **New transaction list**: one card per day with Today / Yesterday headers
  and day totals, place logos with who paid, search, and quick filters
  (All, Expenses, Income, Transfers, per person).
- The version number is shown in the app.

### Changed
- Quick Add no longer opens with the number pad: tap the amount to open it,
  tap Done, anywhere else, or scroll to close it.
- Long-press a category chip (or tap the slider button) to edit categories.

### Fixed
- Spending in a category without a budget no longer turns the background
  amber. With no budgets at all, Home shows "Spent this month" and a calm
  "Set up your budgets" card instead of a negative "safe to spend".

### Under the hood
- Database schema v2 (places) with an automatic upgrade from 0.1.0 data.
- App test suite (migration, categories, places) runs in CI next to the
  TideKit tests; CI screenshots cover the new screens and retry uploads.

## 0.1.0 — Foundation

- Xcode project for iOS 27, Liquid Glass design system and a background
  that tints with the month's budget health.
- Home (safe to spend / ready to assign, budget rings, goals, recent),
  Quick Add with multi-currency support, and a basic Activity list.
- Core Data model ready for iCloud sharing, starter categories, demo data.
- CI on GitHub's Macs: tests, build, and screenshots.
