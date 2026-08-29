# Why this stopped

Stopped in August 2026, before anything was installed or run against a real
account. Written down so that picking it up later starts from what was actually
learned rather than from the original assumption.

## The original idea could not work

The request was an iPhone app that reads Banco Industrial purchase
notifications and logs them to a text file.

**iOS does not allow any app to read another app's notifications.** There is no
public API, no entitlement, and no workaround. This is the single fact the whole
project ran into, and it does not change with effort. Anything that captures
these notifications has to do it somewhere other than the iPhone.

## What was tried instead, and why each fell short

**A Mac reading the notifications.** With iPhone Mirroring, an iPhone's
notifications reach the Mac and land in Notification Center's database, which
can be read. This works, and is implemented in `bridge/`. But it only sees
notifications while the Mac is awake and connected. The Mac here is a MacBook
that gets carried around, so it would have missed most purchases — and a
half-complete expense file is worse than none, because it gets trusted.

**Bank emails parsed in the cloud.** Would have run on Google's servers,
needing no Mac. Banco Industrial sends no per-transaction emails or SMS, only
the Wallet push notification. Ruled out.

**Importing the statement.** The bank's own record: complete, correct, needing
nothing to be running. Implemented in `importer/`, and it was the right answer
on paper. It was never tested against a real Banco Industrial statement, so
whether it reads their format is unknown.

## Where it actually ended

The owner is not a programmer, and each route asked for more setup than the
result was worth: Xcode and a 7-day reinstall cycle for the app, Full Disk
Access and a permanently awake Mac for the notification watcher, a monthly
manual download for the statement importer. The effort never got below the
value of the outcome. That is a fair reason to stop.

## What is worth keeping

- `bridge/` — reads macOS Notification Center. Genuinely useful on a machine
  that stays awake, such as a desktop Mac.
- `importer/` — reads .xlsx and .csv with the standard library alone, works out
  which columns hold what, and merges statements without duplicating rows. The
  most reusable piece, and not specific to this bank.
- `fixtures/samples.json` — real Banco Industrial notification formats,
  transcribed from a screenshot, with the parsing rules they need.

## What was never verified

- The Swift app has never been compiled. No Swift toolchain was available.
- The macOS bridge has never run on a Mac; it was tested against a synthetic
  database.
- The statement importer has never seen a real Banco Industrial statement.

Python tests pass: 22 for the bridge and parser, 21 for the importer.

## If picking this up again

Start with the statement importer, and start by looking at what Bi en Línea
actually exports. If it offers Excel or CSV, `importer/` is close. If PDF is the
only option, that is a different problem and worth deciding on before building
anything.
