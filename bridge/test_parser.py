"""Corpus tests for the reference parser. Run: python3 -m unittest discover bridge"""

import json
import os
import unittest
from datetime import datetime, timezone
from decimal import Decimal

import expense_parser as ep

FIXTURES = os.path.join(os.path.dirname(__file__), "..", "fixtures", "samples.json")
AT = datetime(2026, 8, 28, 14, 3, 11, tzinfo=timezone.utc)


class CorpusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(FIXTURES, encoding="utf-8") as fh:
            cls.samples = json.load(fh)["samples"]

    def test_corpus(self):
        for sample in self.samples:
            with self.subTest(sample["id"]):
                got = ep.parse(sample["text"], source="test", received_at=AT)
                want = sample["expect"]
                self.assertEqual(got.kind, want["kind"], f"{sample['id']}: raw={got.raw!r} reason={got.reason}")
                if "amount" in want:
                    self.assertEqual(got.amount, Decimal(want["amount"]), sample["id"])
                if "currency" in want:
                    self.assertEqual(got.currency, want["currency"], sample["id"])
                if "merchant" in want:
                    self.assertEqual(got.merchant, want["merchant"], sample["id"])
                if "card" in want:
                    self.assertEqual(got.card, want["card"], sample["id"])


class FormatTests(unittest.TestCase):
    def setUp(self):
        self.exp = ep.parse("Chase: You spent $24.50 at STARBUCKS with card ending in 1234",
                            source="Chase", received_at=AT)

    def test_tsv_is_eight_columns(self):
        self.assertEqual(len(ep.format_line(self.exp, "tsv").split("\t")), 8)

    def test_expense_is_negative(self):
        self.assertEqual(ep.format_line(self.exp, "tsv").split("\t")[1], "-24.50")

    def test_credit_is_positive(self):
        credit = ep.parse("Refund of $30.00 from ZARA credited", received_at=AT)
        self.assertEqual(ep.format_line(credit, "tsv").split("\t")[1], "30.00")

    def test_jsonl_roundtrips(self):
        payload = json.loads(ep.format_line(self.exp, "jsonl"))
        self.assertEqual(payload["merchant"], "STARBUCKS")
        self.assertEqual(payload["amount"], -24.5)

    def test_raw_newlines_do_not_break_a_line(self):
        exp = ep.parse("Revolut\nYou spent $8.00 at LIDL", received_at=AT)
        self.assertNotIn("\n", ep.format_line(exp, "tsv"))

    def test_dedupe_key_is_stable_and_distinct(self):
        again = ep.parse(self.exp.raw, source="Chase", received_at=AT)
        self.assertEqual(self.exp.dedupe_key(), again.dedupe_key())
        other = ep.parse("Chase: You spent $99.00 at LIDL", received_at=AT)
        self.assertNotEqual(self.exp.dedupe_key(), other.dedupe_key())


if __name__ == "__main__":
    unittest.main()
