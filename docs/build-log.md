# Build log

## v0.1 — Nov 14, 2026 (MyHealth-app-v0.1.zip)
Fork of the FreeReps iOS app (MIT), targets iOS 26.0, display name "My Health".
Identifiers: `personal.myhealth.a7k2`, widgets `…a7k2.widgets`, app group `group.personal.myhealth.a7k2`; no development team set (user picks own in Xcode).

Decided: hybrid calorie target — BMR (Mifflin-St Jeor) × activity level until 10 of the last 14 days have Watch active calories, then BMR + 14-day Watch average. Pace 0.25/0.5/0.75 kg a week at 7,700 kcal/kg. Minimum 1,200 (female) / 1,500 (male) / 1,350 (other). Macros: protein 1.6 g/kg, fat 25% of calories, carbs the rest.

New code in `app/Sources/FreeReps/Nutrition/`:
- `UserProfile.swift` — profile + ProfileStore (UserDefaults)
- `CalorieCalculator.swift` — target calculation
- `HealthSnapshotService.swift` — today's steps/exercise/active calories/sleep, 14-day history, weight read/write
- `OnboardingView.swift` — setup questionnaire, prefilled from Health
- `TodayView.swift` — Today tab, weight log sheet and 90-day chart

Verification: model and calculator compiled and run with Swift 6.0.3 on Linux; the SwiftUI and HealthKit files were only syntax-checked (no Xcode here). First Xcode build on the Mac is still to do.

## First Xcode build — Nov 17, 2026
Mac: macOS 26.6 (Darwin 25.6), Xcode 27.2 (27B52). Deployment target iOS 26.0 confirmed in both targets.
- `xcodebuild -scheme FreeReps -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO clean build` → **BUILD SUCCEEDED**, 0 errors, 0 compiler warnings. All five Nutrition files compile; Today tab and onboarding are wired into `ContentView`.
- No code changes were needed.
- Built for a real iPhone, not the Simulator: Xcode's CoreSimulator and CoreDevice components on this Mac are older than Xcode 27.2 expects, so the Simulator and device install are unavailable until the components are updated (`sudo xcodebuild -runFirstLaunch`, or accept the "install components" prompt when Xcode opens). HealthKit doesn't work in the Simulator anyway.
- Nov 17: user ran `sudo xcodebuild -runFirstLaunch`; simctl and devicectl now work. No Apple ID in Xcode yet, no signing certificate.
- Nov 17: signed with the user's free Apple ID (Personal Team), bundle ID `personal.myhealth.a7k2` accepted. **Runs on the user's iPhone 13 Pro.** Sync tab shows "Connection failed" as expected: no FreeReps server is set up yet.

## Meal photos, step 1: API key in Settings — Nov 17, 2026
- New `Nutrition/ClaudeSettings.swift`: Keychain storage for the Claude API key (this device only, not iCloud-synced), model choice (Sonnet 5.5 default, Haiku 5.5, Opus 5.5) in UserDefaults, and a free key check via `GET /v1/models/{model}` (anthropic-version `2026-10-21`).
- New `Nutrition/ClaudeSettingsView.swift`, linked from Settings › Meal Photos › Claude API Key. A key the API rejects (401) isn't saved.
- Both files added to `project.pbxproj` by hand (the project doesn't use synced folders).
- Build: succeeded, 0 warnings. Not yet tested on the phone.

## Meal photos, step 2: photo → Claude → confirm → save — Nov 17, 2026
- `Nutrition/MealAnalyzer.swift`: sends the photo (resized to 1568 px, JPEG) to `POST /v1/messages` with the chosen model, effort `medium`, structured output (`output_config.format` JSON schema: title, items with portion/kcal/protein/carbs/fat, confidence, notes). Handles no key, offline, 401/429/5xx, low credit and `refusal`. No server-side fallback: its categories (cyber, frontier LLM) don't apply to food photos.
- `Nutrition/MealStore.swift`: SwiftData `Meal` (items as JSON, 600 px thumbnail), saved locally first, then to Apple Health as one food correlation (dietary energy, protein, carbs, fat). Deleting a meal deletes it from Health too.
- `Nutrition/MealLogSheet.swift`: camera or Photos, an optional note, Analyse, then an editable confirm screen (name, time, every item and number, add/remove items).
- Today: "Meals today" card with Log meal; target card shows eaten vs. target with a progress bar and eaten/target grams per macro. Touch and hold a meal to delete it.
- Info.plist: camera permission text; Health write text now mentions meals. Health write permission for the four nutrition types is requested on the first save.
- Build: succeeded, 0 warnings. Not yet tested on the phone; the API call hasn't been run end to end.
- Deferred: offline queue (right now a failed request leaves the photo on screen to retry), outbox sync to the Mac.

## Meal photos, step 3: offline queue — Nov 17, 2026
- User tested step 2 on the phone: photo → estimate → save → Apple Health all work.
- New `Nutrition/MealQueue.swift`: SwiftData `PendingMeal` (photo, note, time taken, estimate once analysed, last error) and `MealQueue` (NWPathMonitor). Waiting photos are analysed when the network comes back, when the app returns to the foreground, and when Today opens.
- Meal sheet: after an offline or API error, "Save photo for later". A pending photo opens straight on the review screen; saving it logs the meal at the time the photo was taken and removes it from the queue.
- Today: waiting photos appear in "Meals today" with status (waiting for a connection / analysing / ready to check / error). Tap to review, touch and hold to delete.
- Build: succeeded, 0 warnings. Not yet tested on the phone.
- Dropped at the user's request: the 2,230 kcal target question and the 0 active calories check.

## FreeReps server on the Mac — Nov 17, 2026
- Mac: Apple M5, 24 GB, Docker 29.5.2 via Colima (already installed). No Tailscale app on the Mac: the server joins the tailnet itself (tsnet).
- `server/`: `compose.yml` and `config.yaml` from FreeReps' `server/compose.example.yml` / `config.example.yaml` (Tailscale on, `session_timezone: America/New_York`), `.env` with a random `POSTGRES_PASSWORD` (mode 600, git-ignored). `TS_AUTHKEY` left empty: approved through the login link instead, so no auth key is stored.
- Images: `meltforce/freereps:latest` (server 2.2.1), `timescale/timescaledb:latest-pg16`.
- Tailscale: the user created a tailnet, approved the server (machine "freereps"), enabled MagicDNS and HTTPS certificates, installed Tailscale on the iPhone. After a restart the server logs "tsnet server starting … tls=true" with no errors.
- Start/stop: `docker compose up -d` / `docker compose down` in `server/`; data lives in the `pgdata` and `tsnet-state` volumes.
- Nov 17: app connected (Settings host `freereps.<tailnet>.ts.net`, 443, HTTPS); first sync stored ~22k `health_metrics` rows.

## Meal totals to the server — Nov 17, 2026
- The server's `metric_allowlist` already accepts `dietary_energy_consumed`, `dietary_protein`, `dietary_carbohydrates`, `dietary_fat_total`, and the app's `FreeRepsPayload.swift` already maps them. Added the four types to `HealthDataType.swift`, so meals logged from photos now reach the server through the normal sync (as Apple Health nutrition, not as meals).
- Needs the new read permissions (Settings › Apple Health Permissions in the app).
- Build: succeeded, 0 warnings. Verified on the server: one meal (Nov 17, 17:01) arrived as 1,085 kcal, 33 g protein, 97 g carbs, 59 g fat.
- Not covered: meal names, items and photos. The server has no table for them; that would need a change to the FreeReps server (Go) or a separate store.

## Background sync — Nov 17, 2026
- New `Services/BackgroundSync.swift`: HealthKit observer queries with hourly background delivery for steps, active energy, heart rate, weight, dietary energy and sleep. A wake runs the normal incremental `SyncViewModel.runSync()`, skipped while the phone is locked (`isProtectedDataAvailable`), while a sync is running, or within 30 minutes of the last background run. Uses a background task so a sync can finish if the app is suspended.
- Off by default. Settings › Health & Sync › Background Sync turns it on and shows when it last ran.
- `AppDelegate` (via `@UIApplicationDelegateAdaptor`) registers the observers at every launch, which background wakes require.
- Entitlement `com.apple.developer.healthkit.background-delivery` added; a signed build with the free Personal Team accepted it.
- Build: succeeded, 0 warnings. Not yet tested on the phone. iOS decides when to wake the app, so the first background run can take an hour or more.

## Next
- Optional: full meal records (names, items, photos) on the Mac; needs a server change
