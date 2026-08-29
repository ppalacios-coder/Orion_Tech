"""Tests for the statement importer, using synthetic statements in the shapes
Guatemalan bank exports actually take: Spanish accented headings, separate
débito/crédito columns, semicolon separators, Windows-1252 encoding, and dates
written several different ways.
"""

import csv
import tempfile
import unittest
import zipfile
from datetime import datetime
from pathlib import Path

import import_statement as imp
from statement_reader import UnreadableStatement, read_rows

EXCEL_EPOCH = datetime(1899, 12, 30)


def write_csv(path: Path, rows, delimiter=",", encoding="utf-8"):
    text = "\n".join(delimiter.join(str(c) for c in row) for row in rows)
    path.write_bytes(text.encode(encoding))


def write_xlsx(path: Path, rows, date_columns=()):
    """A minimal but genuine .xlsx: shared strings, styles and one sheet."""
    strings, string_index = [], {}

    def share(text):
        if text not in string_index:
            string_index[text] = len(strings)
            strings.append(text)
        return string_index[text]

    sheet_rows = []
    for r, row in enumerate(rows, start=1):
        cells = []
        for c, value in enumerate(row):
            ref = f"{chr(ord('A') + c)}{r}"
            if isinstance(value, datetime):
                serial = (value - EXCEL_EPOCH).days
                cells.append(f'<c r="{ref}" s="1"><v>{serial}</v></c>')
            elif isinstance(value, (int, float)):
                cells.append(f'<c r="{ref}"><v>{value}</v></c>')
            else:
                cells.append(f'<c r="{ref}" t="s"><v>{share(str(value))}</v></c>')
        sheet_rows.append(f'<row r="{r}">{"".join(cells)}</row>')

    ns = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
    sheet = f'<?xml version="1.0"?><worksheet {ns}><sheetData>{"".join(sheet_rows)}</sheetData></worksheet>'
    shared = ('<?xml version="1.0"?><sst ' + ns + f' count="{len(strings)}" uniqueCount="{len(strings)}">'
              + "".join(f"<si><t>{s}</t></si>" for s in strings) + "</sst>")
    # Style 1 uses numFmtId 14 (a built-in date format).
    styles = ('<?xml version="1.0"?><styleSheet ' + ns + '><cellXfs count="2">'
              '<xf numFmtId="0"/><xf numFmtId="14" applyNumberFormat="1"/>'
              '</cellXfs></styleSheet>')

    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("xl/worksheets/sheet1.xml", sheet)
        archive.writestr("xl/sharedStrings.xml", shared)
        archive.writestr("xl/styles.xml", styles)


class ReaderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def test_reads_a_comma_csv(self):
        path = self.dir / "a.csv"
        write_csv(path, [["Fecha", "Descripcion", "Monto"], ["15/01/2026", "SHELL", "200.00"]])
        self.assertEqual(read_rows(path)[1], ["15/01/2026", "SHELL", "200.00"])

    def test_reads_a_semicolon_csv(self):
        path = self.dir / "b.csv"
        write_csv(path, [["Fecha", "Descripcion", "Monto"], ["15/01/2026", "SHELL", "200,00"]], ";")
        self.assertEqual(read_rows(path)[1], ["15/01/2026", "SHELL", "200,00"])

    def test_reads_windows_encoded_accents(self):
        path = self.dir / "c.csv"
        write_csv(path, [["Fecha", "Descripción", "Débito"], ["15/01/2026", "CAFÉ", "26.00"]],
                  encoding="cp1252")
        self.assertEqual(read_rows(path)[0][1], "Descripción")
        self.assertEqual(read_rows(path)[1][1], "CAFÉ")

    def test_reads_an_xlsx_including_styled_dates(self):
        path = self.dir / "d.xlsx"
        write_xlsx(path, [["Fecha", "Descripcion", "Monto"],
                          [datetime(2026, 1, 15), "CIRCUS COFFEE", 26.0]])
        rows = read_rows(path)
        self.assertEqual(rows[0], ["Fecha", "Descripcion", "Monto"])
        self.assertEqual(rows[1][0], "2026-01-15", "a date-styled serial must read as a date")
        self.assertEqual(rows[1][1], "CIRCUS COFFEE")

    def test_old_xls_gives_a_useful_message(self):
        path = self.dir / "e.xls"
        path.write_bytes(b"\xd0\xcf\x11\xe0")
        with self.assertRaises(UnreadableStatement) as caught:
            read_rows(path)
        self.assertIn("save as .xlsx", str(caught.exception))

    def test_pdf_gives_a_useful_message(self):
        path = self.dir / "f.pdf"
        path.write_bytes(b"%PDF-1.4")
        with self.assertRaises(UnreadableStatement) as caught:
            read_rows(path)
        self.assertIn("Excel or CSV", str(caught.exception))


class LayoutTests(unittest.TestCase):
    def test_finds_headers_below_a_title_block(self):
        rows = [["BANCO INDUSTRIAL, S.A."], ["Estado de cuenta"], [],
                ["Fecha", "Descripción", "Débito", "Crédito", "Saldo"],
                ["15/01/2026", "SHELL", "200.00", "", "3,450.20"]]
        layout = imp.find_layout(rows)
        self.assertEqual(layout.header_row, 3)
        self.assertEqual(layout.date, 0)
        self.assertEqual(layout.description, 1)
        self.assertEqual(layout.debit, 2)
        self.assertEqual(layout.credit, 3)

    def test_balance_column_is_never_the_amount(self):
        rows = [["Fecha", "Concepto", "Monto", "Saldo"],
                ["15/01/2026", "SHELL", "200.00", "3450.20"]]
        layout = imp.find_layout(rows)
        self.assertEqual(layout.amount, 2)
        entries, _ = imp.extract(rows, layout, "s.csv", "GTQ")
        self.assertEqual(entries[0].amount, -200.00)

    def test_unrecognised_layout_says_what_to_send(self):
        with self.assertRaises(UnreadableStatement) as caught:
            imp.find_layout([["some", "random", "file"], ["1", "2", "3"]])
        self.assertIn("Send me the first few rows", str(caught.exception))


class ExtractTests(unittest.TestCase):
    def rows_to_entries(self, rows, currency="GTQ"):
        layout = imp.find_layout(rows)
        return imp.extract(rows, layout, "statement.csv", currency)[0]

    def test_debits_are_negative_and_credits_positive(self):
        entries = self.rows_to_entries([
            ["Fecha", "Descripción", "Débito", "Crédito"],
            ["15/01/2026", "SHELL", "200.00", ""],
            ["16/01/2026", "DEVOLUCION ZARA", "", "150.00"],
        ])
        self.assertEqual(entries[0].amount, -200.00)
        self.assertEqual(entries[0].kind, "expense")
        self.assertEqual(entries[1].amount, 150.00)
        self.assertEqual(entries[1].kind, "credit")

    def test_thousands_separators(self):
        entries = self.rows_to_entries([
            ["Fecha", "Concepto", "Monto"],
            ["15/01/2026", "NOTARIA", "1,234.56"],
        ])
        self.assertEqual(entries[0].amount, -1234.56)

    def test_parentheses_and_trailing_minus_mean_negative(self):
        entries = self.rows_to_entries([
            ["Fecha", "Concepto", "Monto"],
            ["15/01/2026", "UNO", "(150.00)"],
            ["16/01/2026", "DOS", "75.00-"],
        ])
        self.assertEqual(entries[0].amount, -150.00)
        self.assertEqual(entries[1].amount, -75.00)

    def test_spanish_month_abbreviations(self):
        entries = self.rows_to_entries([
            ["Fecha", "Concepto", "Monto"],
            ["15/ENE/2026", "SHELL", "200.00"],
        ])
        self.assertEqual(entries[0].date, datetime(2026, 1, 15))

    def test_refunds_in_a_single_amount_column_are_positive(self):
        entries = self.rows_to_entries([
            ["Fecha", "Concepto", "Monto"],
            ["15/01/2026", "ABONO DEVOLUCION COMERCIO", "150.00"],
        ])
        self.assertGreater(entries[0].amount, 0)

    def test_totals_and_heading_rows_are_skipped(self):
        rows = [["Fecha", "Concepto", "Monto"],
                ["15/01/2026", "SHELL", "200.00"],
                ["", "TOTAL", "200.00"],
                ["", "", ""]]
        layout = imp.find_layout(rows)
        entries, skipped = imp.extract(rows, layout, "s.csv", "GTQ")
        self.assertEqual(len(entries), 1)
        self.assertEqual(skipped, 1)

    def test_dollar_and_quetzal_rows_keep_their_currency(self):
        entries = self.rows_to_entries([
            ["Fecha", "Concepto", "Moneda", "Monto"],
            ["15/01/2026", "AMAZON", "USD", "25.00"],
            ["16/01/2026", "SHELL", "Q", "200.00"],
        ])
        self.assertEqual(entries[0].currency, "USD")
        self.assertEqual(entries[1].currency, "GTQ")

    def test_card_digits_are_picked_out_of_the_description(self):
        entries = self.rows_to_entries([
            ["Fecha", "Concepto", "Monto"],
            ["15/01/2026", "SHELL tarjeta terminación 1234", "200.00"],
        ])
        self.assertEqual(entries[0].card, "1234")


class MergeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.master = self.dir / "expenses.csv"
        self.addCleanup(self.tmp.cleanup)

    def statement(self, name, rows):
        path = self.dir / name
        write_csv(path, rows)
        return path

    def run_import(self, *paths, extra=()):
        import subprocess, sys as _sys
        return subprocess.run(
            [_sys.executable, str(Path(imp.__file__)), *[str(p) for p in paths],
             "--out", str(self.master), *extra],
            capture_output=True, text=True, cwd=str(Path(imp.__file__).parent))

    def test_importing_twice_adds_nothing_the_second_time(self):
        path = self.statement("jan.csv", [
            ["Fecha", "Descripción", "Débito"],
            ["15/01/2026", "SHELL", "200.00"],
            ["16/01/2026", "CIRCUS COFFEE", "26.00"],
        ])
        first = self.run_import(path)
        self.assertIn("added 2 transactions", first.stdout, first.stderr)

        second = self.run_import(path)
        self.assertIn("nothing new to add", second.stdout, second.stderr)

        with self.master.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.reader(handle))
        self.assertEqual(rows[0], imp.COLUMNS)
        self.assertEqual(len(rows), 3, "header plus two transactions")

    def test_overlapping_statements_merge_without_duplicates(self):
        first = self.statement("a.csv", [
            ["Fecha", "Descripción", "Débito"],
            ["15/01/2026", "SHELL", "200.00"],
            ["16/01/2026", "CIRCUS COFFEE", "26.00"],
        ])
        second = self.statement("b.csv", [
            ["Fecha", "Descripción", "Débito"],
            ["16/01/2026", "CIRCUS COFFEE", "26.00"],
            ["17/01/2026", "CAFE UFM", "44.00"],
        ])
        self.run_import(first)
        result = self.run_import(second)
        self.assertIn("1 already imported", result.stdout)
        self.assertIn("added 1 transactions", result.stdout)

    def test_dry_run_writes_nothing(self):
        path = self.statement("jan.csv", [
            ["Fecha", "Descripción", "Débito"], ["15/01/2026", "SHELL", "200.00"]])
        result = self.run_import(path, extra=["--dry-run"])
        self.assertIn("would add 1", result.stdout)
        self.assertFalse(self.master.exists())

    def test_rows_are_kept_in_date_order(self):
        path = self.statement("mixed.csv", [
            ["Fecha", "Descripción", "Débito"],
            ["17/01/2026", "CAFE UFM", "44.00"],
            ["15/01/2026", "SHELL", "200.00"],
        ])
        self.run_import(path)
        with self.master.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.reader(handle))[1:]
        self.assertEqual([r[0] for r in rows], ["2026-01-15", "2026-01-17"])


if __name__ == "__main__":
    unittest.main()
