# Getting notifications into the app

iOS has no API that lets an app read another app's push notifications. This is
the central constraint of the whole project, so it is worth being precise about
what is and is not possible:

- **Not possible:** an App Store app that observes your banking app's alerts.
  There is no `NotificationListenerService` equivalent, no Notification Center
  read API, and no entitlement that grants it. Notification Service Extensions
  only see *your own* app's pushes.
- **Not viable:** background OCR or screen recording. iOS does not let an app
  read the screen in the background.
- **Possible:** have something you *can* automate hand the text to this app.

Four routes below, best first.

**If your card alerts come from Apple Wallet** (the notification is grouped
under *Wallet* and shows the card art, as Banco Industrial's do), there is no
SMS or email version of that notification to automate — route 3 is the one that
captures it. Routes 1 and 2 still apply if your bank *also* sends transaction
texts or emails, and they remain the more reliable choice, so it is worth
turning those on at the bank as well.

---

## 1. Bank SMS alerts (recommended)

Most banks will text you on every card transaction. A Shortcuts personal
automation can act on an incoming message without opening anything.

1. Enable per-transaction SMS alerts in your bank's app or website. For Banco
   Industrial that is the alert/notification settings in Bi en Línea or the BI
   app — the same place you would turn on transaction notifications.
2. **Shortcuts ▸ Automation ▸ + ▸ Message.**
3. Set **Sender** to your bank's number or short code. If the number varies, use
   **Message Contains** with a word its alerts always include — for BI,
   `Compra`, `Consumo` or `Q` works well.
4. Choose **Run Immediately** and turn **Notify When Run** off.
5. Add action **Log Expense from Text**.
6. Tap the **Notification Text** field and choose the **Shortcut Input**
   variable. Optionally set **Source** to your bank's name.

Make a purchase (a coffee will do) and check the Log tab.

**Why this is the best option:** fully on-device, survives reboots, works with
the phone locked, needs no second machine.

## 2. Bank email alerts

Identical wiring, using the **Email** automation trigger instead of Message.
Filter by the sender address your bank uses, then pass the email body into
**Log Expense from Text**.

If your iOS version has no Email automation trigger, the equivalent is a Mail
rule on a Mac, or forwarding the alerts to an address you poll — but at that
point route 3 is simpler.

## 3. Real push notifications, via a Mac

This is the only route that reads the actual push alert.

**How it works:** with iPhone Mirroring (macOS 15+), your iPhone's
notifications are forwarded to your Mac and land in Notification Center's
database. `bridge/notification_bridge.py` polls that database, parses banking
alerts with the same rules as the app, and appends them to a text file.

```bash
# 1. Find the identifier. Card alerts posted through Apple Wallet come from
#    Wallet (com.apple.Passbook), not from the bank's own app — confirm here.
python3 bridge/notification_bridge.py --list-apps

# 2. Watch it — check what it would log before writing anything
python3 bridge/notification_bridge.py --bundle-id com.bi.BancoIndustrial --once --dry-run --verbose

# 3. Run it for real
python3 bridge/notification_bridge.py \
    --bundle-id com.bi.BancoIndustrial \
    --out ~/Library/Mobile\ Documents/com~apple~CloudDocs/expenses.txt \
    --currency GTQ
```

Writing into iCloud Drive as above means the file syncs back to your phone.

**Setup requirements**

- macOS 15 or later with iPhone Mirroring set up and notifications forwarded.
- **Full Disk Access** for your terminal: System Settings ▸ Privacy & Security ▸
  Full Disk Access. Without it you get a `cannot read the database` error.
- The script only reads; it never writes to the system database.

**Honest limitations**

- Notification Center's schema is private and undocumented. A macOS update can
  change it and break the bridge.
- It only sees notifications while the Mac is awake and mirroring is connected.
  Alerts that arrive while it is asleep are missed.
- On first run it starts from the newest record, so it will not import history.

**Keeping it running**

```bash
./bridge/install_launchagent.sh --bundle-id com.apple.Passbook \
    --out "$HOME/Library/Mobile Documents/com~apple~CloudDocs/expenses.txt"
```

That writes a LaunchAgent with `RunAtLoad` and `KeepAlive`, starts it, and logs
to `~/Library/Logs/expense-logger-bridge.log`. Remove it with
`./bridge/install_launchagent.sh --uninstall`.

Note that launchd runs its own copy of `python3`, so Full Disk Access granted to
your terminal does not cover it. If the log says it cannot read the database,
grant Full Disk Access to the `python3` binary the installer printed.

**Showing the same log on the phone**

Write the file into iCloud Drive as above, then in the app: Settings ▸ Where the
log lives ▸ *Point at a file in iCloud Drive*. The app keeps access to it across
launches and reads it with file coordination, so it and iCloud's sync do not
collide. Deleting from within the app leaves that file alone.

## 4. Manual capture

For one-offs and for testing: copy the notification text, open the **Test** tab,
tap **Paste from clipboard**, then **Log this now**. The Test tab also shows
exactly how the text was parsed, which is the quickest way to find out why
something did not log the way you expected.

---

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| Automation never runs | **Run Immediately** not selected, or the trigger filter never matches. Check Shortcuts ▸ Automation ▸ the automation ▸ run history. |
| It runs but nothing is logged | The text was ignored or unparsed. Look in `expenses.review.txt` (Log tab ▸ *needing review*) for the reason. |
| Wrong amount logged | Your bank puts the balance before the amount. See [PARSING.md](PARSING.md). |
| Everything logged twice | Two automations are firing. The app suppresses identical text within 120s (Settings ▸ Duplicates); widen the window if needed. |
| Bridge logs nothing | Wrong `--bundle-id`, or Full Disk Access not granted. Run with `--list-apps` and `--verbose`. |
