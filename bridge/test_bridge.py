"""Tests for the macOS bridge, run against a synthetic Notification Center DB.

The real database is macOS-only and private, so these build a stand-in with the
same shape: it verifies the SQL, the nested-plist decoding, the bundle filter
and the resume state, none of which need a Mac.
"""

import argparse
import plistlib
import sqlite3
import tempfile
import unittest
from pathlib import Path

import notification_bridge as nb

BANK = "com.bank.app"
NOISE = "com.example.chat"


WALLET = "com.apple.Passbook"


def make_db(path: Path, records):
    conn = sqlite3.connect(path)
    conn.executescript(
        "CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier TEXT);"
        "CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER,"
        " data BLOB, delivered_date REAL);"
    )
    apps = {}
    for index, (identifier, _, _) in enumerate(records, start=1):
        apps.setdefault(identifier, index)
    for identifier, app_id in apps.items():
        conn.execute("INSERT INTO app VALUES (?, ?)", (app_id, identifier))
    for rec_id, (identifier, title, body) in enumerate(records, start=1):
        # Mirrors the real layout: the text is nested inside a 'req' dict.
        # A tuple of (title, subtitle, body) exercises the three-part form.
        request = ({"titl": title[0], "subt": title[1], "body": body}
                   if isinstance(title, tuple) else {"titl": title, "body": body})
        blob = plistlib.dumps({"req": request}, fmt=plistlib.FMT_BINARY)
        conn.execute(
            "INSERT INTO record VALUES (?, ?, ?, ?)",
            (rec_id, apps[identifier], blob, 776_000_000.0 + rec_id),
        )
    conn.commit()
    conn.close()


def make_args(db, out, **overrides):
    defaults = dict(
        db=str(db), bundle_id=[BANK], out=str(out), format="tsv", currency="EUR",
        interval=1.0, state="", once=True, dry_run=False, list_apps=False, verbose=False,
    )
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


class BridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.db = self.dir / "db"
        self.out = self.dir / "expenses.txt"
        self.addCleanup(self.tmp.cleanup)

    def test_logs_a_bank_notification(self):
        make_db(self.db, [(BANK, "BBVA", "Compra de 45,20 EUR en MERCADONA con tarjeta *1234")])
        state = {"last_rec_id": 0}
        self.assertEqual(nb.process_once(make_args(self.db, self.out), state), 1)

        lines = self.out.read_text().strip().split("\n")
        self.assertEqual(lines[0], nb.ep.HEADERS["tsv"], "header is written once")
        fields = lines[1].split("\t")
        self.assertEqual(fields[1], "-45.20")
        self.assertEqual(fields[2], "EUR")
        self.assertEqual(fields[3], "MERCADONA")
        self.assertEqual(fields[5], BANK)

    def test_ignores_other_apps(self):
        make_db(self.db, [(NOISE, "Chat", "You spent $10.00 at LIDL")])
        self.assertEqual(nb.process_once(make_args(self.db, self.out), {"last_rec_id": 0}), 0)
        self.assertFalse(self.out.exists())

    def test_ignores_non_transactions(self):
        make_db(self.db, [(BANK, "BBVA", "Tu código de verificación es 483920")])
        self.assertEqual(nb.process_once(make_args(self.db, self.out), {"last_rec_id": 0}), 0)

    def test_does_not_relog_on_the_next_poll(self):
        make_db(self.db, [(BANK, "BBVA", "Compra de 10,00 EUR en DIA")])
        state = {"last_rec_id": 0}
        self.assertEqual(nb.process_once(make_args(self.db, self.out), state), 1)
        self.assertEqual(state["last_rec_id"], 1)
        self.assertEqual(nb.process_once(make_args(self.db, self.out), state), 0)
        self.assertEqual(len(self.out.read_text().strip().split("\n")), 2)

    def test_logs_a_wallet_style_card_alert(self):
        make_db(self.db, [(WALLET, ("Banco Industrial", "Circus Coffee"), "GTQ 26.00")])
        args = make_args(self.db, self.out, bundle_id=[WALLET], currency="GTQ")
        self.assertEqual(nb.process_once(args, {"last_rec_id": 0}), 1)

        fields = self.out.read_text().strip().split("\n")[1].split("\t")
        self.assertEqual(fields[1], "-26.00")
        self.assertEqual(fields[2], "GTQ")
        self.assertEqual(fields[3], "Circus Coffee", "the subtitle is the merchant")

    def test_dry_run_writes_nothing(self):
        make_db(self.db, [(BANK, "BBVA", "Compra de 10,00 EUR en DIA")])
        nb.process_once(make_args(self.db, self.out, dry_run=True), {"last_rec_id": 0})
        self.assertFalse(self.out.exists())

    def test_decodes_title_subtitle_and_body_separately(self):
        blob = plistlib.dumps({"req": {"titl": "Banco Industrial", "subt": "Circus Coffee",
                                       "body": "GTQ 26.00"}}, fmt=plistlib.FMT_BINARY)
        self.assertEqual(nb.decode_record(blob), ("Banco Industrial", "Circus Coffee", "GTQ 26.00"))

    def test_survives_an_undecodable_record(self):
        self.assertEqual(nb.decode_record(b"not a plist"), ("", "", ""))
        self.assertEqual(nb.decode_record(b""), ("", "", ""))

    def test_apple_epoch_conversion(self):
        self.assertEqual(nb.apple_time(0).year, 2001)
        self.assertEqual(nb.apple_time(None).tzinfo.utcoffset(None).total_seconds(), 0)


if __name__ == "__main__":
    unittest.main()
