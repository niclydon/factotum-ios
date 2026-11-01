# Automation recipes — feeding ARIA from other apps

iOS gives no app a way to read another app's data. What it does give is **Shortcuts
personal automations**: a trigger fires, and the automation can hand whatever it received to
an app's own action. ARIA ships four background actions for this:

| Action | Use with | Sends |
|---|---|---|
| **Log Notification to ARIA** | *Notification* trigger (iOS 27) | App, Title, Subtitle, Body, Date |
| **Log Purchase to ARIA** | Wallet *Transaction* trigger | Card, Merchant, Amount, Name, optional Date |
| **Log App Event to ARIA** | *App* trigger (is opened / is closed) | App, State |
| **Log Event to ARIA** | any other trigger | Label, Text, optional JSON |

Each action queues the event on the phone (up to 7 days / 5,000 events), tries a short
upload, and always reports success, so an automation never shows an error. Everything else
retries on the next background refresh, app open or silent push.

All recipes start in **Shortcuts → Automation → + (New Automation)**.

## 1. One-time settings

- **Settings → Shortcuts → Advanced → Allow Sharing Large Amounts of Data**: ON.
- In every automation below choose **Run Immediately** and turn **Notify When Run** OFF.
- Give every automation a distinct **Automation** label (the last field of each ARIA
  action). The label is how ARIA and Nexus tell automations apart and notice one going quiet.

## 2. Notifications from an app (iOS 27)

1. Trigger **Notification** → choose the app (Uber, DoorDash, Chase, Ring, an airline …).
   Leave the text filter empty unless you only want some of its notifications.
2. Action **Log Notification to ARIA**:
   - App = the app's name (type it)
   - Title / Subtitle / Body / Date = the matching fields of the **Notification** variable
   - Automation = `<App> notifications` (e.g. `Uber notifications`)
3. One automation per app.

## 3. Wallet purchases

1. Trigger **Transaction** → all cards (or the cards you want) → all categories.
2. Action **Log Purchase to ARIA**: Card, Merchant, Amount and Name from the trigger's
   *Shortcut Input*; Automation = `Wallet taps`. If the trigger exposes a timestamp
   variable, pass it into Date — this protects against iOS delaying background
   automation execution (the tap time can otherwise drift from when the intent
   actually runs); leave it blank and ARIA uses execution time.

## 4. App usage (Screen Time substitute)

1. Trigger **App** → pick the apps → **Is Opened** → action **Log App Event to ARIA**
   (App = the app name, State = Opened, Automation = `App usage`).
2. A second automation for the same apps with **Is Closed** (State = Closed).
   Nexus pairs opens and closes into sessions (`device_app_sessions`).

## 5. Focus

1. Trigger **Focus** → pick a Focus → **When Turning On** → **Log Event to ARIA** with
   Label = `focus`, Text = `<Focus name> on`, Automation = `Focus`.
2. Repeat with **When Turning Off** and Text = `<Focus name> off`.

## 6. CarPlay, charger, Wi-Fi, Bluetooth, NFC

Matching trigger → **Log Event to ARIA** with:

| Trigger | Label | Text |
|---|---|---|
| CarPlay connects / disconnects | `carplay` | `connected` / `disconnected` |
| Charger connected / disconnected | `charger` | `connected` / `disconnected` |
| Wi-Fi joins / leaves a network | `wifi` | the network name |
| Bluetooth device connects | `bluetooth` | the device name |
| NFC tag scanned | `nfc` | the tag's name |

Automation = the label capitalised (`CarPlay`, `Charger`, …).

## 7. Another app's data (Things 3 example)

1. Trigger **Time of Day** 21:00, daily.
2. Things **Find Items** (Completed, today).
3. Action **Log Event to ARIA** with Label = `things`, JSON = the Find Items output (use a
   *Text* action to turn it into JSON if needed), Automation = `Things daily`.

Any app with a Shortcuts action that returns data (Notes *Find Notes*, Day One *Find
Entries*, …) works the same way.

## 8. Checking it works

- **ARIA → Settings → Data Sources → Automations** lists every label with its last event
  and a 24 h count. A gold dot means the automation has gone quiet (at least 5 events so far
  and silent for more than 3× its usual gap, minimum 48 h). Nexus sends a push for the same
  condition once per quiet spell.
- After each iOS update, re-check: NFC and location triggers may turn *Ask Before Running*
  back on, and the Notification trigger's text filter was unreliable in iOS 27 beta 1.

## 9. Labels Nexus files without an LLM

`focus`, `carplay`, `charger`, `wifi`, `bluetooth`, `battery`, `low_power`, `airplane`,
`nfc`, `alarm`, `sleep`, `keyboard`, `screenshot`. Any other label with valid JSON is stored
as-is; other free text (and every notification) is classified by the Forge tagger into
purchase / ride / food delivery / package / travel / bank alert / message / security / other.
Labels starting `aria:` are reserved for the app itself.
