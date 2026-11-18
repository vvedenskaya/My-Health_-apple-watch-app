# My Health

A personal iPhone app that brings together your Apple Watch data, a daily calorie target, a weight log and meal logging from photos. Claude estimates each meal's calories and macros from a photo, you check the numbers, and the meal is saved to Apple Health. Optionally, everything syncs to a small server on your own Mac over a private Tailscale network.

It's a fork of the open-source [FreeReps](https://github.com/meltforce/freereps) iOS app (MIT license, see [app/LICENSE](app/LICENSE)), built for personal use and installed straight from Xcode. It is not on the App Store.

**Contents**

1. [What it does](#what-it-does)
2. [What you need](#what-you-need)
3. [Part 1: Install the app on your iPhone](#part-1-install-the-app-on-your-iphone)
4. [Part 2: Meal photos (Claude API key)](#part-2-meal-photos-claude-api-key)
5. [Part 3: The server on your Mac (optional)](#part-3-the-server-on-your-mac-optional)
6. [Part 4: Tailscale](#part-4-tailscale)
7. [Part 5: Connect the app to the server](#part-5-connect-the-app-to-the-server)
8. [Everyday use](#everyday-use)
9. [Troubleshooting](#troubleshooting)
10. [Costs](#costs)
11. [Privacy and security](#privacy-and-security)
12. [Project layout](#project-layout)

---

## What it does

| Feature | Needs |
|---|---|
| **Today tab:** steps, exercise minutes, active calories and sleep from Apple Health | iPhone (Apple Watch optional) |
| **Calorie target and macros** from a setup questionnaire. It switches to your Apple Watch's measured activity after 10 days of Watch data | iPhone |
| **Weight log** with a 90-day chart, saved to Apple Health | iPhone |
| **Meal photos:** take or pick a photo, Claude estimates the foods, portions, calories, protein, carbs and fat, you correct anything, and it's saved in the app and to Apple Health. Today shows eaten vs. target | Claude API key |
| **Offline queue:** photos taken without signal are analysed once you're back online | Claude API key |
| **Sync to your Mac:** Apple Health data and meal totals go to a FreeReps server on your Mac | Mac server and Tailscale |
| **Background sync:** sends new Health data to the Mac about hourly after you unlock the phone | Mac server and Tailscale |

The first four rows work with just the iPhone. The server is optional.

---

## What you need

| | Notes |
|---|---|
| **A Mac** with **Xcode 27** or newer | Free from the Mac App Store, about 10 GB. |
| **An iPhone on iOS 26 or newer** and a **cable** for it | HealthKit doesn't work in the Simulator, so you need a real phone. |
| **An Apple ID** | A free one works. Apps installed with a free Apple ID stop opening after 7 days until you reinstall them from Xcode. The paid Apple Developer Program ($99/year) removes that limit. |
| **An Apple Watch** (optional) | Without one you still get steps and sleep from the iPhone, but active calories and exercise minutes stay at 0. |
| **A Claude API account** (for meal photos) | At [console.anthropic.com](https://console.anthropic.com). This is separate from a Claude.ai subscription and is pay-as-you-go. |
| **Docker** on the Mac (for the server) | [Docker Desktop](https://www.docker.com/products/docker-desktop/), [OrbStack](https://orbstack.dev), or Colima via Homebrew. |
| **A Tailscale account** (for the server) | Free for personal use, at [tailscale.com](https://tailscale.com). |

---

## Part 1: Install the app on your iPhone

### 1.1 Get the code and open it

```bash
git clone <this repository's URL> my-health
```

```bash
open my-health/app/FreeReps.xcodeproj
```

The project and its targets are still called **FreeReps** inside Xcode. The app shows up on your phone as **My Health**.

### 1.2 First-time Xcode setup

If you've never used Xcode on this Mac, run this once in Terminal. It asks for your Mac password, and nothing shows while you type:

```bash
sudo xcodebuild -runFirstLaunch
```

This installs the parts Xcode needs to talk to an iPhone. If you skip it, Xcode may not see your phone at all.

### 1.3 Add your Apple ID to Xcode

1. In the menu bar, click **Xcode › Settings…** and open the **Accounts** tab.
2. Click **+** (bottom left), choose **Apple Account**, and sign in.
3. Close Settings.

### 1.4 Make the app identifiers your own

Apple requires every app ID to be unique, and the IDs in this repository already belong to someone else. Pick **four random letters or numbers**, for example `q7m3`, and replace `a7k2` with them in these places, keeping them identical everywhere:

| File | Change |
|---|---|
| Xcode › FreeReps project › target **FreeReps** › Signing & Capabilities › **Bundle Identifier** | `personal.myhealth.q7m3` |
| Same, target **FreeRepsWidgets** | `personal.myhealth.q7m3.widgets` |
| `app/Sources/FreeReps/Resources/FreeReps.entitlements` | `group.personal.myhealth.q7m3` |
| `app/Sources/FreeRepsWidgets/FreeRepsWidgets.entitlements` | `group.personal.myhealth.q7m3` |
| `app/Sources/Shared/SyncLink.swift` (`appGroup`) | `group.personal.myhealth.q7m3` |

Or let Terminal do it all at once (macOS `sed`), replacing `q7m3` with your letters:

```bash
cd my-health/app && grep -rl "a7k2" FreeReps.xcodeproj Sources | xargs sed -i '' 's/a7k2/q7m3/g'
```

### 1.5 Choose your signing team

1. In Xcode's left sidebar, click the blue **FreeReps** icon at the very top.
2. Under **TARGETS**, click **FreeReps**, then the **Signing & Capabilities** tab.
3. Tick **Automatically manage signing** and set **Team** to *Your Name (Personal Team)*.
4. Do the same for the **FreeRepsWidgets** target.

A red **"Communication with Apple failed… no devices"** message is normal at this point. It goes away once your iPhone is connected in the next step.

### 1.6 Connect the iPhone

1. Plug the iPhone into the Mac with a cable, **unlock it**, and tap **Trust** when it asks, then enter your passcode. If the Mac asks whether to allow the accessory, click **Allow**.
   - No prompt? Try another cable (many only charge), plug straight into the Mac rather than a hub, and keep the phone unlocked.
2. At the top of the Xcode window, click the device menu (it says *Any iOS Device*) and pick your iPhone.
3. Turn on **Developer Mode** on the iPhone: **Settings › Privacy & Security** › scroll to the bottom › **Developer Mode** › on. The phone restarts; after unlocking, tap **Turn On**.
   - The option only appears after the phone has been connected to Xcode at least once.

### 1.7 Run it

1. In Xcode, press **⌘R** (hold Command, press R), click the **▶** button, or choose **Product › Run**. The first build takes a minute or two.
2. If the iPhone says the developer isn't trusted, open **Settings › General › VPN & Device Management**, tap your Apple ID, tap **Trust**, then press ⌘R again.
3. If Xcode asks whether to stop the running app and launch a new one, choose **Stop**.

### 1.8 First launch on the phone

1. Allow the **Health permissions**. Turn them all on. If asked how far back, choose **All Recorded Data**.
2. Fill in the **setup questionnaire**. Some answers are prefilled from Apple Health. You can change them later under **Today › Edit goals**.

The **Sync** tab shows "Connection failed" until you set up the server in Part 3. That's expected and harmless.

---

## Part 2: Meal photos (Claude API key)

### 2.1 Create a key

1. Sign up at **[console.anthropic.com](https://console.anthropic.com)**.
2. Under **Billing**, add a payment method and a small amount of credit.
3. Recommended: under **Limits**, set a monthly spend limit, for example $5.
4. Under **API Keys**, click **Create Key** and copy it. It starts with `sk-ant-`.

Keep the key private. Don't paste it into chats, files or this repository.

### 2.2 Add it to the app

1. In My Health, go to **Settings › Claude API Key**.
2. Paste the key and tap **Save key**. You should see **"Key works with Sonnet 5.5."** The check is free.
3. Optionally, pick the model:

   | Model | About per photo | Notes |
   |---|---|---|
   | Sonnet 5.5 (default) | $0.008 | Good balance of accuracy and cost |
   | Haiku 5.5 | $0.0004 | Cheapest; less careful with portions |
   | Opus 5.5 | $0.016 | Most capable |

The key is stored in the iPhone's Keychain, on this device only. It isn't synced to iCloud, so on a new phone you enter it again.

### 2.3 Log a meal

1. On **Today**, tap **Log meal** in the "Meals today" card.
2. **Take photo** or **Choose from Photos**. Optionally, add a note about anything the photo can't show, such as "cooked in butter" or "half eaten".
3. Tap **Analyse meal** and wait about 5–20 seconds.
4. Check every item: name, portion, calories, protein, carbs and fat. Remove wrong items, add missing ones, and fix the time if needed.
5. Tap **Save**. The first time, allow Apple Health access for nutrition.

The meal appears on Today (eaten vs. target) and in the **Health** app under **Browse › Nutrition › Energy Consumed**. To delete a meal, touch and hold it on Today; that removes it from Apple Health too.

**No signal?** After a failed analysis, tap **Save photo for later**. It appears on Today as *Waiting for a connection*, is analysed automatically once you're online, and then shows *Ready to check*; tap it to review and save.

---

## Part 3: The server on your Mac (optional)

The server is the open-source [FreeReps server](https://github.com/meltforce/freereps): a Go program with a PostgreSQL/TimescaleDB database, running in Docker. It keeps a copy of your Apple Health data and meal totals on your Mac. It has **no password of its own**: it only accepts devices on your Tailscale network (Part 4).

### 3.1 Install and start Docker

Use any one of these:

- **Docker Desktop:** install it from [docker.com](https://www.docker.com/products/docker-desktop/) and open it.
- **Colima** (no app, command line only):
  ```bash
  brew install colima docker docker-compose
  ```
  ```bash
  brew services start colima
  ```
  `brew services` also starts Colima automatically every time you log in, so the server comes back after a restart.

Check that Docker is running:

```bash
docker info --format '{{.ServerVersion}}'
```

### 3.2 Configure

1. Create the password file from the example:
   ```bash
   cd my-health/server && cp .env.example .env
   ```
2. Open `.env` and replace `change-me` with a long random password. You never type it again. To generate one:
   ```bash
   openssl rand -base64 24
   ```
3. Open `server/config.yaml` and set `session_timezone` to your timezone, for example `"Europe/London"` or `"America/Los_Angeles"`. To see yours:
   ```bash
   readlink /etc/localtime | sed 's|.*zoneinfo/||'
   ```

`.env` is git-ignored. Never commit it.

### 3.3 Start the server

```bash
docker compose up -d
```

The first time, this downloads about 640 MB: the server is about 28 MB and the database about 611 MB. Check that both containers are up:

```bash
docker compose ps
```

The server isn't reachable yet; it needs Tailscale, which comes next.

---

## Part 4: Tailscale

**Why:** Tailscale is a private network between only your own devices. It lets the iPhone reach the server on your Mac **from anywhere** (home Wi-Fi, mobile data, work), encrypts the connection, gives the server a proper HTTPS certificate, and acts as the server's login: only devices signed in to your Tailscale account can connect.

**Your Mac does not need the Tailscale app.** The server joins Tailscale by itself. Only the iPhone needs the app.

### 4.1 Create an account

Sign up at **[tailscale.com](https://tailscale.com)**. Signing in with Google, Apple or Microsoft is fine. The free Personal plan is enough.

**Turn on two-factor authentication** on the account you sign in with. Whoever controls that account can reach your health data.

### 4.2 Add the server

1. Show the server's log:
   ```bash
   docker compose logs freereps | grep login.tailscale.com | tail -1
   ```
2. Copy the `https://login.tailscale.com/a/…` link, open it in your browser (signed in to your Tailscale account), and click **Connect**.
3. In the [Tailscale admin console](https://login.tailscale.com/admin/machines), you should now see a machine called **freereps** marked *Connected*.

### 4.3 Turn on HTTPS (required)

The server refuses to start without it. Its log shows *"you must enable HTTPS in the admin panel"*.

1. In the admin console, open **DNS**.
2. Make sure **MagicDNS** is on.
3. Under **HTTPS Certificates**, click **Enable HTTPS** and confirm.
4. Note your **Tailnet name** near the top of the DNS page, for example `tail1234ab.ts.net`.
5. Restart the server so it picks up the change:
   ```bash
   docker compose restart freereps
   ```
6. Check the log shows `tsnet server starting … tls=true` with no errors after it:
   ```bash
   docker compose logs freereps --since 1m
   ```

Your server's address is **`freereps.` + your Tailnet name**, for example `freereps.tail1234ab.ts.net`.

### 4.4 Add the iPhone

1. Install **Tailscale** from the App Store.
2. Sign in with the **same account**.
3. Allow the VPN configuration when iOS asks, and make sure the switch is on.
4. The admin console's Machines page should now list **2 machines**.

Tailscale on the iPhone can stay on all the time. It only routes traffic to your own devices, not your normal internet traffic.

---

## Part 5: Connect the app to the server

1. In My Health, open **Settings** and tap the top row (FreeReps logo, *freereps.your-tailnet.ts.net*).
2. Set **Host** to your server's address, for example `freereps.tail1234ab.ts.net`. Leave port **443** and HTTPS on.
3. Go back. The dot under the name should turn green: **Connected · Server 2.2.1**.
4. Open the **Sync** tab and tap **Full Sync**. Keep the app open; the first sync sends up to 2 years of Health data and can take a while. Later syncs only send what's new, even though the button still says "Full Sync".
5. For meal totals to sync, allow the nutrition items under **Settings › Apple Health Permissions** (Energy Consumed, Protein, Carbohydrates, Fat).

**Optional: background sync.** Turn on **Settings › Background Sync**. When new Health data appears, iOS wakes the app (at most about hourly, timing decided by iOS) and it sends what's new to the server. It skips while the phone is locked, because iOS doesn't allow reading Health data then, and runs at most every 30 minutes. Expect data to reach the Mac within an hour or a few hours, not instantly. Tap Full Sync when you want it there right away.

**Check the data arrived** (on the Mac):

```bash
cd my-health/server && docker compose exec -T db psql -U freereps -d freereps -c "select metric_name, count(*) from health_metrics group by 1 order by 2 desc limit 10;"
```

---

## Everyday use

- **Every 7 days** (free Apple ID): plug in the iPhone and press **⌘R** in Xcode. Your data stays.
- **Start / stop the server** (in `server/`):
  ```bash
  docker compose up -d
  ```
  ```bash
  docker compose down
  ```
  `down` keeps your data; it lives in the Docker volumes `pgdata` and `tsnet-state`. Only `docker compose down -v` deletes it.
- **Keep the Mac awake** if you want syncs to land while you're away from it. A sleeping Mac means syncs fail until it wakes; the phone catches up afterwards.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `xcodebuild` or Xcode says *CoreSimulator is out of date* or can't load *CoreDevice* | Run `sudo xcodebuild -runFirstLaunch`, or accept Xcode's "install components" prompt. |
| Plugging in the iPhone does nothing | Unlock the phone, try another cable, plug directly into the Mac. If you once tapped "Don't Trust": iPhone **Settings › General › Transfer or Reset iPhone › Reset › Reset Location & Privacy**, then plug in again. |
| **Developer Mode** isn't in Settings | It appears only after the phone has connected to Xcode. Connect it, open Xcode, then check again. |
| *Communication with Apple failed… no devices* | Connect the iPhone and select it in Xcode's device menu; Xcode then registers it. |
| *Bundle identifier is not available* | Use different letters in step 1.4. |
| App won't open: *Untrusted Developer* | iPhone **Settings › General › VPN & Device Management** › your Apple ID › **Trust**. |
| App stopped opening after a week | Free Apple ID expiry. Plug in and press ⌘R. |
| **Active calories / exercise show 0** | Check **Settings › Privacy & Security › Health › My Health** and turn on everything. Without an Apple Watch these stay 0. |
| Meal analysis: *key was rejected* / *credit balance is too low* | Check the key in **Settings › Claude API Key**; add credit at console.anthropic.com › Billing. |
| Meal not in Apple Health | Allow nutrition writes: **Settings › Privacy & Security › Health › My Health**. |
| **Sync tab: "Connection failed"** | Expected before Part 5. Otherwise check: Tailscale switch on the iPhone is on, the Mac is awake, `docker compose ps` shows both containers up, and the host in Settings matches `freereps.<tailnet>.ts.net`. |
| Server log: *you must enable HTTPS in the admin panel* | Do step 4.3, then `docker compose restart freereps`. |
| Server log keeps printing a *login.tailscale.com* link | It hasn't been approved yet; do step 4.2. |

---

## Costs

| | Cost |
|---|---|
| App, Xcode, free Apple ID | Free (reinstall every 7 days) |
| Apple Developer Program | $99/year, optional (removes the 7-day limit, enables TestFlight) |
| Claude API | About $0.008 per photo with Sonnet 5.5: 10 photos a day is under $3 a month. Haiku 5.5 is about $0.0004 per photo. |
| Tailscale | Free Personal plan |
| Server | Runs on your own Mac: free |

---

## Privacy and security

- **Apple Health data** is read on the iPhone. With the server, it goes only to your Mac over Tailscale's encrypted connection. No other cloud service is involved.
- **Meal photos** are sent to Anthropic's API to estimate the meal. Anthropic's API terms and data-retention policy apply. Avoid photos with faces, documents or screens in them.
- **The Claude API key** is in the iPhone's Keychain, this device only. It can spend money on your Anthropic account, so set a spend limit (step 2.1).
- **The server has no password.** Tailscale is its only protection: anyone who can sign in to your Tailscale account, or any device you add to it, can read your data. Use two-factor authentication and don't share your tailnet.
- **Backups:** the server's database lives in a Docker volume on your Mac and is not backed up by default. Apple Health on the phone remains the main copy. Meal names, items and photos are stored only in the app on the phone and are lost if you delete the app.
- **Calorie numbers are estimates**, both the target and the meal analysis. This isn't medical advice. Talk to a doctor or dietitian before a large change in diet, especially below the app's minimum targets.

---

## Project layout

```
app/                    iPhone app (Xcode project "FreeReps", shown as "My Health")
  Sources/FreeReps/
    Nutrition/          Added for My Health: profile, calorie target, Today tab,
                        meal photos (MealAnalyzer), meal storage, offline queue,
                        Claude key settings
    Services/           FreeReps sync to the server, plus BackgroundSync.swift
    Views/, ViewModels/ FreeReps Sync and Settings screens
  Sources/FreeRepsWidgets/  Home Screen widget and Live Activity from FreeReps
server/                 Docker Compose setup for the FreeReps server
  compose.yml, config.yaml, .env.example
docs/build-log.md       What was built, when, and the decisions behind it
HANDOFF.md              Original project brief
```

Building from the command line (no signing, to check that it compiles):

```bash
cd app && xcodebuild -project FreeReps.xcodeproj -scheme FreeReps -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build
```

## Credits

Based on the [FreeReps](https://github.com/meltforce/freereps) iOS app and server by meltforce, which is in turn based on [HealthBeat](https://github.com/kempu/HealthBeat) by kempu. MIT License.
