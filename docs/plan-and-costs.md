# Apple Watch Health App – Plan & Costs (updated Nov 14, 2026)

## Decisions so far
- ONE native iOS app on the iPhone (a PWA cannot read HealthKit), built by forking the open-source **FreeReps iOS app** (github.com/meltforce/freereps, MIT, ~5,900 lines Swift).
- Food logging works regardless of the Mac: the phone calls the Claude API itself, stores locally, syncs to the Mac when reachable.
- Personal use only. Start with a **free Apple ID** (Xcode install, 7-day expiry); decide on the $99 program later.
- Xcode is installed on the Mac.
- **Stay on iOS 26**: the fork's deployment target is lowered from 27.0 to 26.0.

## Facts (verified) vs assumptions
- FACT: No cloud/web API for Health data; must be read on the iPhone via HealthKit (free).
- FACT: HealthKit data cannot be read while the iPhone is locked (encrypted store) — confirmed on Apple's developer forums.
- CORRECTION: "No background sync" is a FreeReps design choice (FreeReps DECISIONS.md 2026-09-25), not an Apple limit. HealthKit background delivery can wake the app after unlock (roughly hourly at most). FreeReps removed it because system-started syncs often hit a locked phone. Our app could re-add it with a "skip if locked" check.
- FACT: macOS has no local HealthKit store; Mac apps can't read Health data (Apple docs + Apple engineer). One GitHub project (Vitalink) claims otherwise for macOS 26+, unverified.
- REPORTED (not tested): iOS 27 Visual Intelligence food photos give rankings, not calorie numbers, and don't write to Health (MacRumors, Sahha). Irrelevant on iOS 26.
- FACT: iOS 27 released Sept 14, 2026, for the same iPhones as iOS 26. FreeReps requires iOS 27 only for its Liquid Glass design; those APIs exist from iOS 26.
- FACT: TestFlight requires the paid $99/yr Apple Developer Program, even for private/internal use. Free accounts get Xcode installs on own devices, valid 7 days. HealthKit and App Groups work on free accounts.

## Architecture
**iPhone – our app (fork of FreeReps iOS)**
- Setup questionnaire (prefill from Health where possible): sex, birth date/age, height, current weight, goal (lose/maintain/gain), target weight, pace, activity level → calorie target + macro split; sensible minimum and pace cap as guardrails
- Calorie target method (proposed): BMR (Mifflin-St Jeor) × activity multiplier on day one; after ~2 weeks switch to BMR + 14-day average of Watch active calories (stable daily target from real data). Optional "earned calories" display. Final choice pending.
- Manual weight entry anytime → written to Apple Health (body mass) → trend chart → target recalculated as weight changes
- Dashboard reads steps / exercise / sleep / active calories directly from HealthKit (works with Mac off)
- Meals tab: photo → Claude API from phone → foods, portions, calories, macros → confirm/adjust; offline queue when no signal
- Local database (SwiftData): profile, meals, photos, weights, cached snapshot
- Writes confirmed meals to Apple Health as dietary energy/macros (needs HealthKit write permission)
- Sync on demand over Tailscale when Mac reachable: existing FreeReps health sync + outbox for meals/photos/profile

**Mac – FreeReps server (optional):** Go + PostgreSQL/TimescaleDB via Docker; backup/history; web dashboard. Could move to Hetzner (~$6–7/mo) or DigitalOcean (~$12/mo).

**Outside:** Claude API (meal photos only)

## Costs
| Item | Cost |
|---|---|
| HealthKit, FreeReps code, Tailscale Personal, Mac as server | Free |
| Free Apple ID install | $0 (reinstall every 7 days) |
| Apple Developer Program (1-year installs, TestFlight) | $99/yr, optional |
| Claude API meal photos | Haiku 5.5 ~$0.0004/photo; Sonnet 5.5 ~$0.008/photo (~$1/mo at 4 meals/day) |
| Optional cloud server | Hetzner ~$6–7/mo (+~$1 backups); DigitalOcean ~$12/mo (+~$2.40) |

## Open questions
- Confirm calorie target method (multiplier → Watch 14-day average hybrid?)
