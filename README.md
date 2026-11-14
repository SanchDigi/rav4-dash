# RAV4 Dash

A live dashboard for a 2026 RAV4 Plug-in Hybrid, read from a Bluetooth OBD-II adapter (built for the **Veepeak OBDCheck BLE**).

- High-tech dark gauges you can rearrange, resize, restyle and remove
- Several layouts (Drive, Efficiency, Engine) that you can rename, add and reorder
- Hybrid stats: hybrid battery %, EV vs engine mode, EV share of the trip, battery used this trip
- Alerts: a tile turns red and the phone buzzes when a value crosses a limit you set
- Check-engine status and trouble codes, with an option to clear them
- Demo mode, so you can try it without the car
- A CarPlay version built from Apple's standard screens (see "CarPlay" below)

---

## 1. One-time setup on your Mac

1. **Install Xcode** from the Mac App Store. Open it once and let it install the iOS components it asks for.
2. **Download this code.** Open the Terminal app and paste:
   ```
   git clone https://github.com/SanchDigi/rav4-dash.git
   open rav4-dash/RAV4Dash.xcodeproj
   ```
   (If macOS asks to install "command line developer tools", click Install and run the commands again.)
3. **Sign in with your Apple ID** in Xcode:
   - In the left sidebar, click the blue **RAV4Dash** project icon at the top.
   - Under **Targets**, click **RAV4Dash**, then the **Signing & Capabilities** tab.
   - Next to **Team**, choose **Add an Account…**, sign in with your Apple ID, then pick **"Your Name (Personal Team)"**.
   - If Xcode says the bundle identifier isn't available, open `Config/Signing.xcconfig` in the sidebar and change `com.sanchdigi.rav4dash` to something unique, like `com.sanchdigi.rav4dash2`.

## 2. Put it on your iPhone

1. Plug your iPhone into the Mac with a cable. Tap **Trust** on the phone if asked.
2. On the iPhone, turn on **Settings → Privacy & Security → Developer Mode**. The phone restarts.
3. In Xcode's top toolbar, pick your iPhone as the run destination, then press the **▶ Run** button.
4. The first time, the iPhone may say "Untrusted Developer". Go to **Settings → General → VPN & Device Management**, tap your Apple ID, and tap **Trust**. Then open the app again.

With a free Apple ID, the app stops opening after 7 days. Plug in the phone and press ▶ again to renew it. A paid Apple Developer account ($99/year) makes it last a year.

## 3. Use it in the car

1. Plug the Veepeak into the OBD-II port under the steering wheel.
2. Turn the RAV4 on so it shows **READY**.
3. Open RAV4 Dash and tap **CONNECT ADAPTER** at the top left. Pick the Veepeak from the list.
   - You don't pair it in iPhone Settings. The app connects to it directly.
   - Close other OBD apps first. The adapter only talks to one app at a time.
4. Next time, the app reconnects on its own when you start the car.

Tip: turn the phone sideways in a dash mount for the 4-column layout. The screen stays on while the app is open.

**Try it without the car:** tap the connection button, then **Try demo mode**.

### Editing the dashboard

- Tap the **pencil** to edit.
- **Drag** a tile to move it. Tap **×** to remove it. Tap the **1×1 / 2×1 / 2×2** chip to resize it.
- **Tap a tile** to change its style (ring, arc, bar, digital, graph) or set warning limits.
- **ADD GAUGE** adds a new stat. **LAYOUTS** renames, adds, reorders or deletes layouts.
- Tap **DONE** when finished. Everything is saved on the phone.

### What your RAV4 will report

Standard OBD-II readings that should work: engine RPM, throttle, engine load, coolant, intake air and outside temperature, 12-volt battery voltage, fuel level, air flow and manifold pressure.

These depend on the car and will show **N/A** if the RAV4 doesn't report them: hybrid battery % and fuel rate. Drive mode, EV share and battery used are worked out by the app from engine RPM and the hybrid battery reading.

Not included yet: electric motor power, hybrid battery temperature and EV range. These need Toyota-specific codes that aren't public for the 2026 model. They can be added later after testing in the car.

---

## CarPlay

The CarPlay version uses Apple's standard screens: a **Gauges** grid (the first 8 tiles of the current layout), a **Live Data** list, a **Codes** page, and pop-up warnings. Layouts are edited on the iPhone.

**Try it in the Simulator (works now):**
1. In Xcode, pick any iPhone **Simulator** as the run destination and press ▶.
2. In the app, turn on demo mode.
3. In the Simulator's menu bar choose **I/O → External Displays → CarPlay**.

**In your car:** Apple has to approve the app for CarPlay first. That needs a paid Apple Developer account. Request the "CarPlay driving task" permission at https://developer.apple.com/contact/carplay/. Once approved, open the RAV4Dash target's **Build Settings**, search for "Code Signing Entitlements", and set it to `Config/CarPlay-Simulator.entitlements` for all builds, not just the Simulator.

Until then, the iPhone app works normally and CarPlay just doesn't list it.

---

## TestFlight from GitHub (no Mac needed)

GitHub builds the app on its own Macs every time code is pushed (the **Actions** tab shows the result). It can also upload the app to TestFlight. This needs a paid Apple Developer account and a one-time setup:

1. **Create the app record.** In [App Store Connect](https://appstoreconnect.apple.com) go to **Apps → + → New App**. Choose iOS, name it "RAV4 Dash", and pick the bundle ID `com.sanchdigi.rav4dash`. For SKU, enter anything, like `rav4dash`.
2. **Create an API key.** In App Store Connect go to **Users and Access → Integrations → App Store Connect API → Team Keys**. Click **+**, name it "GitHub", and set Access to **Admin**. Download the `.p8` file (you can only download it once). Note the **Key ID** and the **Issuer ID** shown at the top of the page.
3. **Find your Team ID** at [developer.apple.com/account](https://developer.apple.com/account) under **Membership details**.
4. **Add four secrets on GitHub.** In this repository go to **Settings → Secrets and variables → Actions → New repository secret**:
   - `ASC_KEY_ID`: the Key ID
   - `ASC_ISSUER_ID`: the Issuer ID
   - `APPLE_TEAM_ID`: your Team ID
   - `ASC_KEY_P8`: the whole contents of the `.p8` file, including the `BEGIN` and `END` lines. Open it in TextEdit to copy it.
5. **Run it.** Go to the **Actions** tab → **Build** → **Run workflow**. After about 10 minutes the build appears in App Store Connect under **TestFlight**. Add yourself as an internal tester there, then install it with the TestFlight app on your iPhone.

## Updating

When there's new code, run this in Terminal, then press ▶ in Xcode again:
```
cd rav4-dash
git pull
```
If `git pull` complains about local changes to the project file (from picking your Team), run `git checkout RAV4Dash.xcodeproj`, then `git pull`, and pick your Team again.

## Troubleshooting

- **The adapter isn't in the list:** make sure the car is on and the Veepeak's light is on. Close other OBD apps. Check **Settings → RAV4 Dash → Bluetooth** is allowed.
- **"No reply from the car":** the car needs to be on (READY), not just accessory mode. Unplug the adapter, plug it back in, and try again.
- **A tile says N/A:** your car doesn't report that reading over standard OBD-II.

## How the code is organized

| Folder | What's in it |
|---|---|
| `RAV4Dash/OBD` | Bluetooth connection, ELM327 commands, reply parsing, the list of stats, demo data |
| `RAV4Dash/Layout` | Tiles, layouts, default layouts, grid placement |
| `RAV4Dash/UI` | Dashboard, gauges, edit screens, connect and trouble-code screens |
| `RAV4Dash/CarPlay` | CarPlay screens and gauge images |
| `Config` | Info.plist, signing settings, CarPlay entitlement |
