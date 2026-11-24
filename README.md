# Tide

A calm, Liquid Glass budget app for couples, for iOS 27.

Track income, expenses, savings, investments and debts, budget each category
by month, and see net worth, cash flow and trends over time. Euro first, with
any currency allowed for spending abroad.

See [docs/PLAN.md](docs/PLAN.md) for the full product plan and milestones.

## Run it on your iPhone

1. Open `Tide.xcodeproj` in **Xcode 27**.
2. Select the **Tide** target → *Signing & Capabilities* → choose your
   **Team** (a free Apple ID works for installing on your own phone). If the
   bundle ID `app.tide.Tide` is taken, change it to something unique, e.g.
   `com.yourname.tide`.
3. Plug in your iPhone (or pick it over Wi-Fi), select it as the run
   destination, and press **Run**.

### Demo data

To look around with a realistic month of sample data, edit the scheme
(*Product → Scheme → Edit Scheme → Run → Arguments*) and tick the
`-demo YES` argument. Demo data lives in memory only and never touches your
real data.

Other launch arguments (used by CI screenshots):
`-tab home|activity|plan|wealth|reports`, `-quickadd YES`,
`-mode limits|everyDollar`.

## Project layout

```
Tide.xcodeproj          Xcode project (folders are synced automatically)
Tide/
  App/                  App entry, app-wide model, month snapshot
  DesignSystem/         Glass components, animated background, palette
  Features/             Home, Quick Add, Activity, … one folder per area
  Persistence/          Core Data schema (in code), entities, starter categories, demo data
Packages/TideKit/       Pure Swift logic: money, currencies, months, budget engine (+ tests)
.github/workflows/      CI: tests, build, simulator screenshots
```

## CI

Every push runs on GitHub's macOS runners:

1. `swift test` for TideKit
2. builds the app for the iOS 27 simulator
3. launches it with demo data and takes screenshots in light and dark mode

Screenshots are attached to the workflow run and also committed to the
`ci-screenshots` branch (one folder per branch).
