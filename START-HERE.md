# Start here

This turns your Banco Industrial purchase alerts into a plain text file that
fills itself in.

**You only need Part A.** It takes about 20 minutes on your Mac and involves no
programming. Part B is an optional iPhone app that shows the same file more
nicely.

There is a friendlier illustrated version of this guide with tick-boxes — ask
for the setup guide link if you do not have it.

---

## Before you start

All four must be true:

- Your Mac runs **macOS 15 (Sequoia)** or newer — Apple menu ▸ About This Mac.
- Your Mac has an **Apple chip** (M1/M2/M3/M4) or a T2 chip.
- iPhone and Mac use the **same Apple Account**, with two-factor on.
- You can find the **iPhone Mirroring** app in your Applications folder.

If iPhone Mirroring is missing, stop — the rest will not work.

---

## Part A — get it recording

**1. Link your iPhone to your Mac.**
Open **iPhone Mirroring** on the Mac and follow its setup. Say yes to
notifications. Then check System Settings ▸ Notifications ▸ *Allow notifications
from iPhone* is on. Confirm a real notification reaches the Mac before going on.

**2. Download the files.**
On the Mac, open
<https://github.com/ppalacios-coder/Orion_Tech/tree/claude/iphone-expense-logging-app-yuiy8q>,
click the green **Code** button, then **Download ZIP**. Unzip it and put the
folder in Documents.

**3. Double-click the setup file.**
Inside the `bridge` folder, double-click **`Setup Expense Logger.command`**.
A Terminal window opens and asks you questions.

If macOS refuses to open it, right-click the file ▸ **Open** ▸ **Open**.

**4. Install developer tools if asked.**
If it says Python is missing, click **Install** in the window that appears, wait,
then double-click the setup file again.

**5. Allow Terminal to read notifications.**
If setup stops for this, it opens the right Settings page. Switch **Terminal**
on in Full Disk Access. If Terminal is not listed: **+**, then Command-Shift-G,
type `/System/Applications/Utilities`, pick Terminal. Quit Terminal
(Command-Q), then run the setup file again.

**6. Answer three questions.**
- Which app sends the alerts → pick **`com.apple.Passbook`** (Apple Wallet).
- Where to save → press Return for iCloud Drive.
- It prints the purchases it *would* record. If they look right, type `y`.

If those preview lines look wrong, close the window and send them to me.

**7. Allow Python too.**
Setup prints a path like `/usr/bin/python3` and copies it. Add it to the same
Full Disk Access list: **+**, Command-Shift-G, Command-V, Return, switch on.

**8. Check it.**
Make a small purchase. Within ~15 seconds, Finder ▸ iCloud Drive ▸
`expenses.txt` should end with that purchase.

Done. It restarts by itself when the Mac turns on.

To stop it later: double-click **`Stop Expense Logger.command`**. Your file is
kept.

---

## What it cannot do

- Purchases made while the **Mac is asleep or off are missed**, and are not
  caught up afterwards.
- It reads an undocumented part of macOS, so a macOS update could break it.
  If purchases stop appearing, check
  `~/Library/Logs/expense-logger-bridge.log`.

---

## Part B — the optional iPhone app

Read this first: the app only *displays* the same file, more nicely, with
totals and Siri. With a free Apple account **it stops working after 7 days**
and must be reinstalled from the Mac. A paid developer account ($99/year)
extends that to a year. If reading `expenses.txt` in the Files app is enough,
you are finished.

1. Install **Xcode** from the App Store (large — allow an hour). Open it once
   and accept the licence.
2. Double-click `ExpenseLogger.xcodeproj`.
3. Click the blue **ExpenseLogger** icon at the top of the left sidebar ▸
   **Signing & Capabilities**. Tick *Automatically manage signing*, add your
   Apple Account under **Team**, and change **Bundle Identifier** from
   `com.example.ExpenseLogger` to something unique of your own.
4. Plug in the iPhone, unlock it, pick it in the device menu at the top, press
   **▶**. On the phone: Settings ▸ General ▸ VPN & Device Management ▸ your
   account ▸ **Trust**.
5. In the app: **Settings** tab ▸ *Point at a file in iCloud Drive* ▸ choose
   `expenses.txt`.

If Xcode shows red errors, copy the first one and send it to me. This part has
never been run on a real Mac, so errors here are expected and quick to fix.

---

## If you get stuck

Send a photo or copy of whatever the Terminal window says, and the step number
you were on. That is normally enough to tell you exactly what to change.
