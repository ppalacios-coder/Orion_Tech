# Expense Logger

Turns Banco Industrial transactions into a spending file you own.

**Start with [START-HERE.md](START-HERE.md).** It covers the route that actually
works for a carried MacBook: importing the Bi en Línea statement
(`importer/`). The notification-capture pieces below are kept for a machine that
stays awake, and are not the recommended path.

Every alert it receives is parsed into amount, currency, merchant, card and
timestamp, then appended as one line to `expenses.txt` in Files ▸ On My iPhone ▸
Expense Logger.

```
timestamp                  amount   currency  merchant        card  source  conf  raw
2026-08-28T12:45:11-06:00  -15.00   GTQ       Parqueo Cayala        Wallet  0.90  Banco Industrial Parqueo Cayala GTQ 15.00
2026-08-28T12:16:04-06:00  -26.00   GTQ       Circus Coffee         Wallet  0.90  Banco Industrial Circus Coffee GTQ 26.00
2026-08-28T09:11:44-06:00  -44.00   GTQ       Cafe UFM              Wallet  0.90  Banco Industrial Cafe UFM GTQ 44.00
```

## Read this first: what iOS will and will not do

**No iOS app can read another app's push notifications.** There is no public
API for it — nothing equivalent to Android's `NotificationListenerService`.
That is an Apple platform restriction, and no amount of code in this repo can
work around it. Any App Store app claiming to do this is doing something else.

So this app does not hook your banking app. It is built to be *fed*, and the
Setup tab and [docs/TRIGGERS.md](docs/TRIGGERS.md) cover the four routes that
actually work:

| Route | Reliability | Needs |
| --- | --- | --- |
| **Bank SMS alerts** → Shortcuts automation | Reliable, fully on-device | SMS alerts enabled at your bank |
| **Bank email alerts** → Shortcuts automation | Reliable, fully on-device | Email alerts enabled at your bank |
| **Real push notifications** → Mac bridge | Best-effort | A Mac awake and running iPhone Mirroring |
| **Manual paste** | Always works | You, doing it |

Most banks can send an SMS or email per transaction, and where that is offered
route 1 is the best option — fully on-device, no Mac involved.

**Banco Industrial is not one of them.** Its card alerts arrive through Apple
Wallet and it offers no per-transaction SMS, so route 3 is the only automatic
one. The setup below is written for that case.

## Setup: Banco Industrial + a Mac

**On the Mac, once — build and install the app**

1. Open `ExpenseLogger.xcodeproj` in Xcode 16+.
2. Target ▸ Signing & Capabilities: pick your team, change the bundle
   identifier off `com.example.ExpenseLogger`.
3. Run it on your iPhone. With a free Apple ID the app stops working after
   7 days and needs reinstalling; a paid developer account gives you a year.

**On the Mac — set the bridge running**

4. Turn on iPhone Mirroring and let notifications forward to the Mac.
5. Grant Full Disk Access to your terminal (System Settings ▸ Privacy &
   Security ▸ Full Disk Access), then find which app posts your card alerts:

   ```bash
   python3 bridge/notification_bridge.py --list-apps
   ```

   Wallet alerts come from Wallet (`com.apple.Passbook`), not a BI app.

6. Check what it would log before it writes anything:

   ```bash
   python3 bridge/notification_bridge.py \
       --bundle-id com.apple.Passbook --once --dry-run --verbose
   ```

7. Install it as a LaunchAgent, writing into iCloud Drive so the file reaches
   your phone:

   ```bash
   ./bridge/install_launchagent.sh --bundle-id com.apple.Passbook \
       --out "$HOME/Library/Mobile Documents/com~apple~CloudDocs/expenses.txt"
   ```

   It starts immediately, restarts after a reboot, and logs to
   `~/Library/Logs/expense-logger-bridge.log`.

**On the iPhone — point the app at that file**

8. Settings ▸ Where the log lives ▸ **Point at a file in iCloud Drive**, and
   choose `expenses.txt`. Leave Format on tab-separated, which is what the
   bridge writes.

The app now shows the same log the Mac is writing, with totals, export and
Siri. Deleting from within the app never touches that file.

**What this does and does not get you**

- Transactions are logged automatically while the Mac is awake with mirroring
  connected. Alerts that arrive while it is asleep never reach the Mac and are
  missed — reconcile those against Wallet's own transaction list on the card.
- Notification Center's database is private and undocumented; a macOS update
  can change it. If logging stops, check the bridge log first.
- The Test tab is always there for anything you want to add by hand.

## Quick start

1. Open `ExpenseLogger.xcodeproj` in Xcode 16 or later.
2. Select the `ExpenseLogger` target ▸ Signing & Capabilities, pick your team,
   and change the bundle identifier from `com.example.ExpenseLogger` to
   something of your own.
3. Run it on your iPhone (iOS 17+). A free Apple ID works; the app expires
   after 7 days and needs reinstalling unless you have a paid developer account.
4. Open the **Test** tab, paste a real notification from your bank, and check
   the amount and merchant come out right.
5. Open the **Setup** tab and wire up a trigger.

## What is in here

```
ExpenseLogger/            The iOS app (SwiftUI, iOS 17+)
  Parsing/                Notification text → structured expense
  Storage/                The log file (local or iCloud), dedupe, settings
  Intents/                App Intents — how Shortcuts talks to the app
  Views/                  Log, Test, Setup and Settings tabs
Config/Info.plist         App metadata (kept out of the synchronized group)
ExpenseLoggerTests/       XCTest suites
importer/                 Statement → spending spreadsheet (the recommended route)
  Import Statement.command  Double-click to import; no typing
bridge/                   macOS notification bridge + reference parser (Python)
  install_launchagent.sh  Keeps the bridge running across reboots
fixtures/samples.json     Parser corpus, shared by the Swift and Python tests
docs/                     Trigger setup and parser tuning
```

## Tuned for Banco Industrial (Guatemala)

BI card alerts arrive through **Apple Wallet**, in Apple's three-part layout —
issuer, merchant, amount, each on its own line, with no sentence to read:

```
Banco Industrial
Circus Coffee
GTQ 26.00
```

There is no verb or preposition here, so the parser reads the **shape** instead
of the wording: when the amount sits alone on its own line, the merchant is the
last meaningful line above it, and the first line is skipped as the issuer name.
When the parts are available separately — as they are to the Mac bridge — the
subtitle is used directly, which is more reliable still.

This matters for which trigger works. **Wallet alerts have no SMS or email
equivalent**, so routes 1 and 2 only apply if BI *also* sends you per-transaction
texts or emails (worth turning on — they are the most reliable option). For the
Wallet notifications in particular, the Mac bridge is the route that captures
them, and it watches Wallet rather than a BI app.

The parser also handles BI's sentence-style alerts:

- **Quetzales**, in the forms Guatemalan banks use: `Q1,234.56`, `Q. 45.00`,
  `GTQ 350.00`. GTQ groups with a comma, so `Q1,234.56` reads as 1234.56, not 1.23.
- **Dollar accounts** stay in dollars: `US$25.00` logs as USD, not GTQ.
- **BI wording**: *compra, consumo, transacción, retiro, transferencia, débito,
  rebajo, cobro*, and *acreditamiento / depósito* as money in.
- **Card digits** from `tarjeta terminación 1234`, preferred over an account
  number in the same alert (`cuenta *4567, tarjeta terminación 1234` → `1234`).
- **Security alerts ignored**: `Su token de seguridad es …`, `Ingreso exitoso a
  Bi en Línea`, `Su saldo disponible es …`.

> The Wallet samples in `fixtures/samples.json` are transcribed from real BI
> notifications. The sentence-style ones are built from Guatemalan banking
> conventions and have not been confirmed against a live alert — if BI sends you
> those too, paste one into the **Test** tab and check it.

Default currency is GTQ (Settings ▸ Parsing).

## The parser

Handles both `1.234,56` and `1,234.56` conventions, English and Spanish alert
wording, refunds as positive amounts, and card digits. It deliberately **ignores**
one-time codes, sign-in alerts, balance updates and promotions, so a passcode
SMS never lands in your expense log.

It also picks the right number when an alert contains two — `You spent $12.00 at
CVS. Available balance: $1,203.11` logs `12.00`.

Anything it is unsure about goes to `expenses.review.txt` rather than being
dropped. See [docs/PARSING.md](docs/PARSING.md) to tune it for your bank.

## App Intents

Available in Shortcuts once the app is installed:

- **Log Expense from Text** — the one automations call. Runs in the background.
- **Append Raw Text to Expense Log** — no parsing, for when you are still
  working out your bank's format.
- **Get Expense Log File** — returns the file, to mail or back up.
- **Get Spend Total** — today / week / month / all time.

## Tests

```bash
python3 -m unittest discover -s bridge -t bridge -v      # parser + bridge, 22 tests
python3 -m unittest discover -s importer -t importer -v  # statement importer, 21 tests
xcodebuild test -scheme ExpenseLogger \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The Swift and Python parsers are checked against the same
`fixtures/samples.json`, so a rule change that breaks one breaks the other.

## Privacy

Everything stays on your device. There is no network code in the app, no
account, and no analytics. The log file is yours; delete it in Settings.
