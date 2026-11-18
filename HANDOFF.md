# Handoff: "My Health" iOS app (Apple Watch data + meal photo calories)

You're picking up a personal project started in Claude chat. Read this file in full, then start with "Your first task" below.

## What we're building
One native iPhone app for personal use (not the App Store). It:
- reads Apple Watch / Apple Health data (steps, exercise minutes, active calories, sleep) via HealthKit
- sets a daily calorie target and macros from a setup questionnaire
- logs weight manually and writes it to Apple Health
- (next) logs meals from a photo: phone → Claude API → foods, portions, calories, macros → user confirms → saved locally and written to Apple Health

A PWA was ruled out: there is no web/cloud API for Health data. HealthKit can only be read on the iPhone, and only while it's unlocked.

## Code base
- Fork of the **FreeReps iOS app** (github.com/meltforce/freereps, MIT license, ~5,900 lines of Swift).
- v0.1 was delivered as `MyHealth-app-v0.1.zip`. Unzip it and run Claude Code from the folder that contains `FreeReps.xcodeproj`. `SETUP.md` in the zip has the install steps.
- Deployment target lowered from iOS 27.0 to **iOS 26.0** (the user stays on iOS 26; the Liquid Glass APIs FreeReps uses exist from iOS 26).
- Display name "My Health". Bundle ID `personal.myhealth.a7k2`, widgets `personal.myhealth.a7k2.widgets`, app group `group.personal.myhealth.a7k2`.
- No development team is set: the user signs with a **free Apple ID** (apps expire after 7 days; HealthKit and App Groups work on free accounts). Both targets (FreeReps, FreeRepsWidgets) need the team chosen in Signing & Capabilities. The paid $99/yr program (needed for TestFlight) is deferred.

New code from v0.1 is in `app/Sources/FreeReps/Nutrition/`:
- `UserProfile.swift`: profile + ProfileStore (UserDefaults)
- `CalorieCalculator.swift`: target calculation
- `HealthSnapshotService.swift`: today's steps/exercise/active calories/sleep, 14-day history, weight read/write
- `OnboardingView.swift`: setup questionnaire, prefilled from Health
- `TodayView.swift`: Today tab, weight log sheet, 90-day weight chart

The Sync and Settings tabs are unchanged FreeReps code.

**Verification status:** the model and calculator compiled and ran with Swift 6.0.3 on Linux. The SwiftUI and HealthKit files were only syntax-checked. **The project has never been built in Xcode.** Expect compile errors.

## Decisions already made
- **Calorie target (hybrid):** BMR (Mifflin-St Jeor) × activity multiplier until 10 of the last 14 days have Watch active calories; then BMR + the 14-day Watch active-calorie average.
- Pace: 0.25 / 0.5 / 0.75 kg per week, at 7,700 kcal per kg.
- Minimum target: 1,200 kcal (female) / 1,500 (male) / 1,350 (other).
- Macros: protein 1.6 g/kg body weight, fat 25% of calories, carbs the rest.
- Questionnaire accepts ages 18–100; warns if the target weight is below the healthy range for the user's height.
- Example sanity check: 30-year-old woman, 65 kg, 165 cm, lightly active, losing ~0.5 kg/week → about 1,330 kcal/day.
- Meal logging must work without the Mac: the phone calls the Claude API directly, stores locally, syncs later.
- Claude API cost estimate: Haiku 5.5 ~$0.0004 per photo, Sonnet 5.5 ~$0.008 per photo.

## Facts worth knowing
- HealthKit data can't be read while the iPhone is locked.
- "No background sync" in FreeReps is their design choice (their DECISIONS.md, 2026-09-25), not an Apple limit. HealthKit background delivery can wake the app after unlock (roughly hourly at most). We may re-add it with a "skip if locked" check.
- macOS has no HealthKit store; the Mac can't read Health data itself.
- The optional FreeReps server (Go + PostgreSQL/TimescaleDB in Docker) runs on the user's Mac, reached over Tailscale. Not set up yet.

## Your first task
1. Confirm the folder layout and find `FreeReps.xcodeproj`.
2. Build from the command line, e.g.
   `xcodebuild -project FreeReps.xcodeproj -scheme FreeReps -destination 'generic/platform=iOS Simulator' build`
   (list schemes with `xcodebuild -list` if the name differs).
3. Fix every compile error and warning in the new Nutrition files (and anything the iOS 26 target change broke). Rebuild until it's clean.
4. Then help the user sign with their Apple ID and run it on their iPhone (Developer Mode on; trust the profile under Settings › General › VPN & Device Management). If Xcode rejects the bundle ID, change the `a7k2` suffix to something unique.

## Roadmap after the build is clean
1. **Meal photos:** camera → Claude API from the phone → list of foods with portions, calories, protein/carbs/fat → confirm/adjust screen → save to a local store (SwiftData) and write to Apple Health (dietary energy, protein, carbohydrates, fat; needs HealthKit write permission) → show eaten vs target on Today. Offline queue when there's no signal. The API key must not be hard-coded in the repo; let the user enter it in Settings and keep it in the Keychain.
2. **Outbox sync** of meals/photos/profile to the FreeReps server on the Mac when reachable.
3. Optional: background HealthKit sync after unlock.

## Working notes
- The user isn't an iOS developer: explain Xcode steps plainly and give exact clicks when they must do something in Xcode or on the phone.
- Keep a short build log (e.g. `BUILD-LOG.md`) of versions and decisions as you go.
