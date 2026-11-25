# Working on Tide

## How we work

- **Plan first, build only on "run".** When the owner asks for features or
  changes, write up the plan (what, where, open questions) and wait. Start
  changing code only after they say **run**.
- **Every release bumps the version** in all of these, together:
  - `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`, the build number) in
    `Tide.xcodeproj/project.pbxproj` — app and test targets
  - `CHANGELOG.md` (new section at the top)
  - the version line in `README.md`
  - `docs/PLAN.md` roadmap status
  - a line in `.github/release-tags.txt` (`v<version> <commit>`) once the
    release commit is green. Neither this environment nor the workflow token
    can push tags (GitHub blocks tags on commits with workflow files), so the
    owner creates them on GitHub → Releases; the CI step only tries and warns.
- The app shows its version via `AppInfo` (Settings → About, Home footer).

## Project facts

- Native iOS 27, SwiftUI + Liquid Glass. Mac app planned (v0.7): keep new
  views free of iPhone-only APIs where it's cheap.
- Pure logic lives in `Packages/TideKit` (no Core Data/SwiftUI) with Swift
  Testing tests; app-level tests live in `TideTests/`.
- Core Data schema is built in code (`Tide/Persistence/TideModel.swift`).
  **Never edit an old schema version** — add a new version and keep the old
  one so `StoreMigrator` can upgrade existing stores. Follow the CloudKit
  rules noted there (optional attributes or defaults, optional inverse
  relationships, no unique constraints).
- Xcode uses folder-synced groups: new files under `Tide/` or `TideTests/`
  are picked up without editing the project file.
- CI (`.github/workflows/ios.yml`) runs on GitHub macOS runners: TideKit
  tests, app build + tests, simulator screenshots (published to the
  `ci-screenshots` branch), and release tags. If the runner lacks Xcode 27
  it tests against the newest SDK it has.
- Launch arguments for demos/screenshots: `-demo YES`, `-tab`, `-quickadd YES`,
  `-mode everyDollar`, `-activity places`, `-detail YES`, `-sheet settings|categories`.
