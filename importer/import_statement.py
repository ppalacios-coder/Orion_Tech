"""Turn a Banco Industrial statement into a running expense file.

Works out which columns hold the date, description and amount, normalises the
numbers, and merges the rows into one master CSV. Re-importing a statement you
have already imported adds nothing, so overlapping downloads are safe.

    python3 import_statement.py ~/Downloads/movimientos.xlsx
    python3 import_statement.py ~/Downloads/*.csv --out ~/expenses.csv
    python3 import_statement.py statement.csv --dry-run
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import re
import sys
import unicodedata
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "bridge"))

from statement_reader import UnreadableStatement, read_rows  # noqa: E402
import expense_parser as ep  # noqa: E402

COLUMNS = ["date", "amount", "currency", "description", "card", "source", "kind", "id"]

# --- column naming ---------------------------------------------------------

DATE_HEADERS = ["fecha", "date", "f. operacion", "fecha operacion", "fecha de operacion",
                "fecha transaccion", "dia"]
DESC_HEADERS = ["descripcion", "description", "concepto", "detalle", "comercio",
                "referencia", "establecimiento", "transaccion", "operacion", "memo"]
AMOUNT_HEADERS = ["monto", "importe", "valor", "amount", "cantidad", "total"]
DEBIT_HEADERS = ["debito", "debe", "cargo", "cargos", "debit", "retiro", "retiros"]
CREDIT_HEADERS = ["credito", "haber", "abono", "abonos", "credit", "deposito", "depositos"]
CURRENCY_HEADERS = ["moneda", "currency", "divisa"]
# Never an amount, however much it looks like one.
BALANCE_HEADERS = ["saldo", "balance", "saldo disponible", "nuevo saldo"]


def fold(text: str) -> str:
    """Lowercase and strip accents, so 'Débito' matches 'debito'."""
    stripped = unicodedata.normalize("NFKD", text or "")
    stripped = "".join(c for c in stripped if not unicodedata.combining(c))
    return re.sub(r"\s+", " ", stripped).strip().lower()


def header_matches(cell: str, names: list[str]) -> bool:
    folded = fold(cell)
    return any(folded == n or folded.startswith(n + " ") or n in folded for n in names)


# --- dates -----------------------------------------------------------------

DATE_FORMATS = [
    "%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%d.%m.%Y",
    "%d/%m/%y", "%d-%m-%y", "%m/%d/%Y", "%Y/%m/%d",
    "%d/%b/%Y", "%d-%b-%Y", "%d %b %Y", "%Y-%m-%d %H:%M:%S",
]


def parse_date(value: str) -> datetime | None:
    text = (value or "").strip()
    if not text:
        return None
    text = re.sub(r"\s+", " ", text)
    for fmt in DATE_FORMATS:
        try:
            return datetime.strptime(text, fmt)
        except ValueError:
            continue
    # Guatemalan statements sometimes write "15/ENE/2026".
    months = {"ene": 1, "feb": 2, "mar": 3, "abr": 4, "may": 5, "jun": 6,
              "jul": 7, "ago": 8, "sep": 9, "set": 9, "oct": 10, "nov": 11, "dic": 12}
    match = re.match(r"^(\d{1,2})[/\- ]([A-Za-zÁÉÍÓÚáéíóú]{3,})[/\- ](\d{2,4})$", text)
    if match:
        month = months.get(fold(match.group(2))[:3])
        if month:
            year = int(match.group(3))
            year += 2000 if year < 100 else 0
            try:
                return datetime(year, month, int(match.group(1)))
            except ValueError:
                return None
    return None


def looks_like_date(value: str) -> bool:
    return parse_date(value) is not None


# --- layout detection ------------------------------------------------------

@dataclass
class Layout:
    header_row: int
    date: int
    description: int
    amount: int | None = None
    debit: int | None = None
    credit: int | None = None
    currency: int | None = None

    def describe(self) -> str:
        parts = [f"date=col{self.date + 1}", f"description=col{self.description + 1}"]
        if self.amount is not None:
            parts.append(f"amount=col{self.amount + 1}")
        if self.debit is not None:
            parts.append(f"debit=col{self.debit + 1}")
        if self.credit is not None:
            parts.append(f"credit=col{self.credit + 1}")
        if self.currency is not None:
            parts.append(f"currency=col{self.currency + 1}")
        return ", ".join(parts)


def find_layout(rows: list[list[str]]) -> Layout:
    """Locate the header row and work out what each column holds."""
    for index, row in enumerate(rows[:40]):
        cells = [fold(c) for c in row]
        if sum(1 for c in cells if c) < 2:
            continue

        date_col = next((i for i, c in enumerate(row) if header_matches(c, DATE_HEADERS)), None)
        if date_col is None:
            continue

        desc_col = next((i for i, c in enumerate(row) if header_matches(c, DESC_HEADERS)), None)
        debit_col = next((i for i, c in enumerate(row) if header_matches(c, DEBIT_HEADERS)), None)
        credit_col = next((i for i, c in enumerate(row) if header_matches(c, CREDIT_HEADERS)), None)
        amount_col = next((i for i, c in enumerate(row)
                           if header_matches(c, AMOUNT_HEADERS)
                           and not header_matches(c, BALANCE_HEADERS)), None)
        currency_col = next((i for i, c in enumerate(row) if header_matches(c, CURRENCY_HEADERS)), None)

        if desc_col is None or (amount_col is None and debit_col is None and credit_col is None):
            continue
        return Layout(index, date_col, desc_col, amount_col, debit_col, credit_col, currency_col)

    raise UnreadableStatement(
        "could not find the column headings. Send me the first few rows of the "
        "file and I will teach it this layout."
    )


# --- rows ------------------------------------------------------------------

@dataclass
class Entry:
    date: datetime
    amount: float          # negative = money out
    currency: str
    description: str
    card: str
    source: str
    kind: str

    @property
    def identifier(self) -> str:
        basis = f"{self.date:%Y-%m-%d}|{self.amount:.2f}|{fold(self.description)}"
        return hashlib.sha1(basis.encode("utf-8")).hexdigest()[:12]

    def as_row(self) -> list[str]:
        return [f"{self.date:%Y-%m-%d}", f"{self.amount:.2f}", self.currency,
                self.description, self.card, self.source, self.kind, self.identifier]


def cell(row: list[str], index: int | None) -> str:
    if index is None or index >= len(row):
        return ""
    return (row[index] or "").strip()


def to_amount(text: str, currency: str) -> float | None:
    """Read a statement amount, honouring parentheses and trailing minus signs."""
    raw = (text or "").strip()
    if not raw:
        return None
    negative = raw.startswith("(") and raw.endswith(")") or raw.endswith("-") or raw.startswith("-")
    cleaned = raw.strip("()").rstrip("-").lstrip("-").strip()
    cleaned = re.sub(r"[^\d.,]", "", cleaned)
    if not cleaned:
        return None
    value = ep._normalize_amount(cleaned, currency)
    if value is None:
        return None
    return -abs(float(value)) if negative else float(value)


def extract(rows: list[list[str]], layout: Layout, source: str,
            default_currency: str) -> tuple[list[Entry], int]:
    entries: list[Entry] = []
    skipped = 0

    for row in rows[layout.header_row + 1:]:
        if not any((c or "").strip() for c in row):
            continue

        when = parse_date(cell(row, layout.date))
        if when is None:
            skipped += 1
            continue

        currency = cell(row, layout.currency).upper() or default_currency
        if currency in ("Q", "QUETZALES", "QUETZAL"):
            currency = "GTQ"
        elif currency in ("US$", "USD$", "DOLARES", "DÓLARES"):
            currency = "USD"

        amount = None
        if layout.debit is not None or layout.credit is not None:
            debit = to_amount(cell(row, layout.debit), currency)
            credit = to_amount(cell(row, layout.credit), currency)
            if debit:
                amount = -abs(debit)
            elif credit:
                amount = abs(credit)
        if amount is None and layout.amount is not None:
            value = to_amount(cell(row, layout.amount), currency)
            if value is not None:
                # A single column of positive numbers on a card statement means
                # charges; refunds are identified by their wording.
                description = cell(row, layout.description)
                is_credit = any(k in fold(description) for k in ep.CREDIT_KEYWORDS)
                amount = abs(value) if is_credit else (value if value < 0 else -value)

        if amount is None or amount == 0:
            skipped += 1
            continue

        description = re.sub(r"\s+", " ", cell(row, layout.description)).strip()
        card = ""
        card_match = ep.CARD_CONTEXT_RE.search(description) or ep.CARD_RE.search(description)
        if card_match:
            card = card_match.group(1)

        entries.append(Entry(
            date=when,
            amount=amount,
            currency=currency,
            description=description or "(no description)",
            card=card,
            source=source,
            kind="credit" if amount > 0 else "expense",
        ))

    return entries, skipped


# --- master file -----------------------------------------------------------

def load_existing(path: Path) -> tuple[list[list[str]], set[str]]:
    if not path.exists():
        return [], set()
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.reader(handle))
    if rows and rows[0] == COLUMNS:
        rows = rows[1:]
    return rows, {r[-1] for r in rows if r}


def write_master(path: Path, rows: list[list[str]]) -> None:
    rows.sort(key=lambda r: (r[0], r[3]))
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    with temporary.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(COLUMNS)
        writer.writerows(rows)
    temporary.replace(path)


def summarise(entries: list[Entry]) -> str:
    if not entries:
        return "nothing to add"
    spent = -sum(e.amount for e in entries if e.amount < 0)
    received = sum(e.amount for e in entries if e.amount > 0)
    first, last = min(e.date for e in entries), max(e.date for e in entries)
    line = (f"{len(entries)} transactions, {first:%d %b %Y} to {last:%d %b %Y}, "
            f"{spent:,.2f} out")
    return line + (f", {received:,.2f} in" if received else "")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("statements", nargs="+", help="Statement files (.xlsx, .csv, .tsv).")
    parser.add_argument("--out", default="~/expenses.csv", help="Master file to build up.")
    parser.add_argument("--currency", default="GTQ", help="Assumed currency when absent.")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be added.")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    master = Path(args.out).expanduser()
    existing_rows, seen = load_existing(master)
    added: list[list[str]] = []
    total_duplicates = 0
    failures = 0

    for name in args.statements:
        path = Path(name).expanduser()
        try:
            rows = read_rows(path)
            layout = find_layout(rows)
            entries, skipped = extract(rows, layout, path.name, args.currency)
        except UnreadableStatement as exc:
            print(f"✗ {path.name}: {exc}", file=sys.stderr)
            failures += 1
            continue

        fresh = [e for e in entries if e.identifier not in seen]
        duplicates = len(entries) - len(fresh)
        total_duplicates += duplicates

        for entry in fresh:
            seen.add(entry.identifier)
            added.append(entry.as_row())

        print(f"✓ {path.name}: {summarise(entries)}")
        if args.verbose:
            print(f"    layout: {layout.describe()}")
            if skipped:
                print(f"    {skipped} rows without a usable date or amount (headings, totals)")
        if duplicates:
            print(f"    {duplicates} already imported, left alone")
        if args.verbose:
            for entry in fresh[:5]:
                print(f"    {entry.date:%Y-%m-%d}  {entry.amount:>10,.2f} {entry.currency}  {entry.description[:40]}")

    if args.dry_run:
        print(f"\nwould add {len(added)} new transactions to {master} (nothing written)")
        return 1 if failures else 0

    if added:
        write_master(master, existing_rows + added)
        print(f"\nadded {len(added)} transactions — {master} now holds "
              f"{len(existing_rows) + len(added)}")
    else:
        print("\nnothing new to add")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
