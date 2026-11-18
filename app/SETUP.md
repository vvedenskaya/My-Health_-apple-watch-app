# My Health – install on your iPhone

This is a personal app built on the open-source FreeReps iOS app (MIT license, see LICENSE).

## First install
1. Unzip, then open `FreeReps.xcodeproj` in Xcode.
2. Xcode › Settings › Accounts: add your Apple ID if it is not there.
3. Click the blue **FreeReps** project icon at the top of the left sidebar, then the **Signing & Capabilities** tab.
4. For the **FreeReps** target and then the **FreeRepsWidgets** target: tick *Automatically manage signing* and choose your name under **Team**.
5. If Xcode says the bundle identifier is not available, change `a7k2` to any other letters in three places, keeping them the same everywhere:
   - Bundle Identifier of FreeReps: `personal.myhealth.XXXX`
   - Bundle Identifier of FreeRepsWidgets: `personal.myhealth.XXXX.widgets`
   - App Groups (both targets) and `Sources/Shared/SyncLink.swift`: `group.personal.myhealth.XXXX`
6. Connect the iPhone by cable, unlock it, and pick it in the device menu at the top of the window.
   The first time, the iPhone asks to turn on Developer Mode (Settings › Privacy & Security › Developer Mode) and restarts.
7. Press ▶ Run.
8. On the iPhone, the first launch is blocked until you trust yourself:
   Settings › General › VPN & Device Management › your Apple ID › Trust.
9. Open **My Health**, allow the Health permissions, and fill in the questionnaire.

## Every 7 days (free Apple ID)
Connect the phone and press ▶ Run again. Your data stays.

## What is in this version
- Today tab: daily calorie target, steps, exercise, active calories, sleep, weight log with trend
- Setup questionnaire (Today › Edit goals to change it)
- Sync and Settings tabs: unchanged from FreeReps, only needed once a FreeReps server runs on the Mac

Not yet: meal photos, saving meals to Apple Health.
