"""Read a bank statement into rows of text cells, using only the standard library.

macOS ships Python without openpyxl, pandas or anything else, and asking someone
to install packages is a barrier. So .xlsx is unzipped and parsed directly — it
is a zip of XML — and .csv is sniffed for its separator and encoding.
"""

from __future__ import annotations

import csv
import io
import re
import zipfile
from datetime import datetime, timedelta
from pathlib import Path
from xml.etree import ElementTree

SHEET_NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"

# Excel counts days from 1899-12-30 (the 1900 leap-year bug is baked in).
EXCEL_EPOCH = datetime(1899, 12, 30)
# Serial numbers outside this range are almost certainly amounts, not dates.
EXCEL_DATE_MIN, EXCEL_DATE_MAX = 25_000, 60_000     # 1968 … 2064


class UnreadableStatement(Exception):
    """The file exists but is not in a form we can read."""


# --------------------------------------------------------------------- CSV

def _decode(raw: bytes) -> str:
    """Bank exports are frequently Windows-1252, not UTF-8."""
    for encoding in ("utf-8-sig", "utf-8", "cp1252", "latin-1"):
        try:
            return raw.decode(encoding)
        except UnicodeDecodeError:
            continue
    return raw.decode("latin-1", errors="replace")


def _sniff_delimiter(text: str) -> str:
    sample = "\n".join(text.splitlines()[:20])
    try:
        return csv.Sniffer().sniff(sample, delimiters=",;\t|").delimiter
    except csv.Error:
        # Fall back to whichever candidate appears most often.
        counts = {d: sample.count(d) for d in ",;\t|"}
        best = max(counts, key=lambda d: counts[d])
        return best if counts[best] else ","


def read_csv(path: Path) -> list[list[str]]:
    text = _decode(path.read_bytes())
    delimiter = _sniff_delimiter(text)
    return [[cell.strip() for cell in row]
            for row in csv.reader(io.StringIO(text), delimiter=delimiter)]


# -------------------------------------------------------------------- XLSX

def _column_index(reference: str) -> int:
    """'C7' -> 2. Cells can be sparse, so positions must be explicit."""
    letters = re.match(r"([A-Z]+)", reference or "")
    if not letters:
        return 0
    index = 0
    for char in letters.group(1):
        index = index * 26 + (ord(char) - ord("A") + 1)
    return index - 1


def _shared_strings(archive: zipfile.ZipFile) -> list[str]:
    try:
        xml = archive.read("xl/sharedStrings.xml")
    except KeyError:
        return []
    strings = []
    for item in ElementTree.fromstring(xml).findall(f"{SHEET_NS}si"):
        # A string can be split across several runs; join their text.
        strings.append("".join(node.text or "" for node in item.iter(f"{SHEET_NS}t")))
    return strings


def _first_sheet_name(archive: zipfile.ZipFile) -> str:
    names = [n for n in archive.namelist() if n.startswith("xl/worksheets/sheet")]
    if not names:
        raise UnreadableStatement("this .xlsx file contains no worksheet")
    return sorted(names)[0]


def _date_styles(archive: zipfile.ZipFile) -> set[int]:
    """Style indexes whose number format looks like a date."""
    try:
        xml = archive.read("xl/styles.xml")
    except KeyError:
        return set()
    root = ElementTree.fromstring(xml)

    date_formats = set(range(14, 23)) | set(range(45, 48))     # Excel built-ins
    for fmt in root.iter(f"{SHEET_NS}numFmt"):
        code = (fmt.get("formatCode") or "").lower()
        if re.search(r"(?<!\\)[dmy]", code) and "0.00" not in code:
            date_formats.add(int(fmt.get("numFmtId", "0")))

    styles = set()
    cell_xfs = root.find(f"{SHEET_NS}cellXfs")
    if cell_xfs is not None:
        for index, xf in enumerate(cell_xfs.findall(f"{SHEET_NS}xf")):
            if int(xf.get("numFmtId", "0")) in date_formats:
                styles.add(index)
    return styles


def read_xlsx(path: Path) -> list[list[str]]:
    try:
        archive = zipfile.ZipFile(path)
    except zipfile.BadZipFile as exc:
        raise UnreadableStatement(
            "this does not look like a real .xlsx file — if the bank gave you an "
            "old .xls, open it and re-save as .xlsx or .csv"
        ) from exc

    with archive:
        strings = _shared_strings(archive)
        date_styles = _date_styles(archive)
        root = ElementTree.fromstring(archive.read(_first_sheet_name(archive)))

        rows: list[list[str]] = []
        for row_node in root.iter(f"{SHEET_NS}row"):
            cells: list[str] = []
            for cell in row_node.findall(f"{SHEET_NS}c"):
                position = _column_index(cell.get("r", ""))
                while len(cells) < position:
                    cells.append("")
                cells.append(_cell_text(cell, strings, date_styles))
            rows.append(cells)
        return rows


def _cell_text(cell, strings: list[str], date_styles: set[int]) -> str:
    kind = cell.get("t")

    if kind == "inlineStr":
        return "".join(node.text or "" for node in cell.iter(f"{SHEET_NS}t")).strip()

    value_node = cell.find(f"{SHEET_NS}v")
    if value_node is None or value_node.text is None:
        return ""
    value = value_node.text.strip()

    if kind == "s":
        try:
            return strings[int(value)].strip()
        except (ValueError, IndexError):
            return ""
    if kind == "str":
        return value

    # A number that is styled as a date is a date.
    try:
        style = int(cell.get("s", "-1"))
    except ValueError:
        style = -1
    if style in date_styles:
        try:
            serial = float(value)
            if EXCEL_DATE_MIN <= serial <= EXCEL_DATE_MAX:
                return (EXCEL_EPOCH + timedelta(days=serial)).strftime("%Y-%m-%d")
        except ValueError:
            pass
    return value


# ------------------------------------------------------------------ router

def read_rows(path: Path) -> list[list[str]]:
    """Read any supported statement into rows of text cells."""
    if not path.exists():
        raise UnreadableStatement(f"no such file: {path}")

    suffix = path.suffix.lower()
    if suffix in (".xlsx", ".xlsm"):
        return read_xlsx(path)
    if suffix in (".csv", ".tsv", ".txt"):
        return read_csv(path)
    if suffix == ".xls":
        raise UnreadableStatement(
            "old .xls files cannot be read directly. Open it in Numbers or Excel "
            "and save as .xlsx or .csv, then try again."
        )
    if suffix == ".pdf":
        raise UnreadableStatement(
            "PDF statements cannot be read yet. If Bi en Línea offers Excel or CSV, "
            "download that instead — it is far more reliable than reading a PDF."
        )
    raise UnreadableStatement(f"unsupported file type: {suffix or 'no extension'}")
