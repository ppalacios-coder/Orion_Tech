# Expense Logger

An iPhone app that turns bank transaction alerts into a plain text file you own.

Every alert it receives is parsed into amount, currency, merchant, card and
timestamp, then appended as one line to `expenses.txt` in Files ▸ On My iPhone ▸
Expense Logger.

```
timestamp                  amount   currency  merchant          card  source  conf  raw
2026-08-28T14:03:11+02:00  -45.20   EUR       MERCADONA         1234  BBVA    1.00  BBVA: Compra de 45,20 EUR…
2026-08-28T18:22:04+02:00  -9.99    GBP       NETFLIX.COM             Monzo   0.90  Payment of £9.99 to NETFLIX…
2026-08-29T10:15:44+02:00  30.00    USD       ZARA              1234  Chase   1.00  Refund of $30.00 from ZARA…
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

Most banks can send an SMS or email per transaction. Turning that on and using
route 1 or 2 gets you the same result as intercepting the push, on-device, with
no Mac involved. **Start there.**

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
  Storage/                The log file, duplicate suppression, settings
  Intents/                App Intents — how Shortcuts talks to the app
  Views/                  Log, Test, Setup and Settings tabs
Config/Info.plist         App metadata (kept out of the synchronized group)
ExpenseLoggerTests/       XCTest suites
bridge/                   macOS notification bridge + reference parser (Python)
fixtures/samples.json     Parser corpus, shared by the Swift and Python tests
docs/                     Trigger setup and parser tuning
```

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
python3 -m unittest discover -s bridge -t bridge -v   # parser + bridge, 15 tests
xcodebuild test -scheme ExpenseLogger \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

The Swift and Python parsers are checked against the same
`fixtures/samples.json`, so a rule change that breaks one breaks the other.

## Privacy

Everything stays on your device. There is no network code in the app, no
account, and no analytics. The log file is yours; delete it in Settings.
