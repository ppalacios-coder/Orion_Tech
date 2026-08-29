# Start here

This turns your Banco Industrial statement into a spending spreadsheet that
lives in your Google Drive.

**About 15 minutes the first time, then 2 minutes a month.** No programming.

There is a friendlier version of this guide with tick-boxes — ask for the setup
guide link if you do not have it.

---

## Why the statement and not the notifications

The original plan was to catch each purchase notification as it happened. Three
things ruled that out:

- **iPhone apps cannot read other apps' notifications.** Apple does not allow
  it. No app can, not just this one.
- **A Mac can read them, but only while awake.** On a MacBook you carry, most
  purchases would happen while it is shut.
- **A half-complete expense file is worse than none**, because you would trust
  it.

Your statement is the bank's own record: every transaction, correct amounts,
nothing missed. You trade instant for complete.

---

## Part A — import your first statement

**1. Download the files.** On the Mac, open
<https://github.com/ppalacios-coder/Orion_Tech/tree/claude/iphone-expense-logging-app-yuiy8q>,
click the green **Code** button, then **Download ZIP**. Unzip it and put the
folder in Documents.

**2. Download your statement from Bi en Línea.** Find your card or account and
look for **Movimientos** or **Estado de cuenta**. If it offers a format, choose
**Excel or CSV**, not PDF. Grab several past months too — you can import them
all and start with real history.

If PDF is the only option, stop and tell me. Send me one and I will say whether
it can be read reliably.

**3. Double-click the import file.** In the folder you unzipped, open the
`importer` folder and double-click **`Import Statement.command`**.

If macOS refuses to open it, right-click ▸ **Open** ▸ **Open**.

**4. Install developer tools if asked.** Click **Install**, wait, then
double-click the import file again.

**5. Answer two questions.**
- Which file → type the number of your statement, or drag the file into the
  window.
- Where your expense file should live → pick the number next to **Google
  Drive**. It remembers, so you are only asked once.

It then shows what it found — count, dates, totals, first few rows — **before
writing anything**. Check the amounts against your statement. If they match,
type `y`.

**6. Open your file.** In your Google Drive folder, double-click
`expenses.csv`. It opens in Numbers, Excel or Google Sheets.

Next month: download the new statement, double-click the same file. Anything
already imported is skipped, so overlapping statements are safe.

---

## Worth knowing

- It is only as current as your last import. Import mid-month if you want a
  mid-month view — importing twice costs nothing.
- Descriptions read the way the bank writes them. Tidying or categorising them
  is easy to add — just ask.
- Cash spending never appears, because the bank never sees it.

---

## Two things to skip

**The Mac notification watcher** (`bridge` folder) reads your Wallet alerts live,
but only while the Mac is awake and connected to your iPhone. On a MacBook you
carry, it would miss most purchases and leave you with a file you cannot trust.
Do not install it. It becomes worth having if you ever have a desktop Mac that
stays on.

**The iPhone app** (`ExpenseLogger` folder) only displays a file that something
else fills in — it cannot read bank notifications, and nothing on iOS can. It
needs Xcode and, on a free Apple account, stops working every 7 days.

Both work and both are kept, so nothing is lost if your situation changes.

---

## If you get stuck

| What you see | What to do |
| --- | --- |
| "could not find the column headings" | Send me the first few rows of your statement. Quick to add. |
| "old .xls files cannot be read" | Open in Numbers or Excel, save as `.xlsx` or `.csv`. |
| "PDF statements cannot be read yet" | Look for an Excel/CSV option; if there is none, send me the PDF. |
| Preview amounts look wrong | Type `n` so nothing is written, and send me what it printed. |
| "nothing new to add" | Those rows were already imported. Check `expenses.csv`. |

Send a copy of whatever the black window says, plus the first four or five rows
of your statement including the headings. That is almost always enough.
