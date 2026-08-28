#!/usr/bin/env python3
"""Append bank push notifications to the expense log, from a Mac.

iOS gives no app access to another app's notifications. The one way to see real
push alerts is on a Mac: with iPhone Mirroring (macOS 15+) your iPhone's
notifications are forwarded to the Mac and stored in Notification Center's
database. This script polls that database, parses banking alerts with the same
rules as the iOS app, and appends them to a text file.

Caveats, honestly stated:
  * Notification Center's schema is private and undocumented. Apple can change
    it in any macOS update and this script will need adjusting.
  * It only sees notifications while the Mac is awake and iPhone Mirroring is
    connected. It is not a substitute for the on-device Shortcuts triggers.
  * The terminal running it needs Full Disk Access
    (System Settings ▸ Privacy & Security ▸ Full Disk Access).

Usage:
    python3 notification_bridge.py --list-apps
    python3 notification_bridge.py --bundle-id com.bi.BancoIndustrial --out ~/expenses.txt
    python3 notification_bridge.py --bundle-id com.bi.BancoIndustrial --once --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import plistlib
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import expense_parser as ep  # noqa: E402

# Notification Center timestamps are seconds since 2001-01-01 UTC.
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)
DEFAULT_STATE = Path.home() / ".expense-logger-bridge.json"


def default_db_path() -> Path | None:
    """Notification Center's database lives under the per-user Darwin dir."""
    try:
        base = subprocess.run(
            ["getconf", "DARWIN_USER_DIR"], capture_output=True, text=True, check=True
        ).stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None
    path = Path(base) / "com.apple.notificationcenter" / "db2" / "db"
    return path if path.exists() else None


def connect(db_path: Path) -> sqlite3.Connection:
    # Read-only: never write to a system database.
    return sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=5)


def apple_time(value) -> datetime:
    try:
        return APPLE_EPOCH + timedelta(seconds=float(value))
    except (TypeError, ValueError):
        return datetime.now(timezone.utc)


def find_text(node, keys=("titl", "subt", "body")) -> dict:
    """Notification payloads are nested binary plists; dig out the text keys."""
    found = {}

    def walk(value):
        if isinstance(value, dict):
            for key, item in value.items():
                if key in keys and isinstance(item, str) and key not in found:
                    found[key] = item
                else:
                    walk(item)
        elif isinstance(value, (list, tuple)):
            for item in value:
                walk(item)

    walk(node)
    return found


def decode_record(blob: bytes) -> tuple[str, str]:
    """Return (title, body) for a record blob, best effort."""
    if not blob:
        return "", ""
    try:
        payload = plistlib.loads(blob)
    except Exception:
        return "", ""
    text = find_text(payload)
    title = " ".join(part for part in (text.get("titl"), text.get("subt")) if part)
    return title.strip(), (text.get("body") or "").strip()


def load_state(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(path: Path, state: dict) -> None:
    try:
        path.write_text(json.dumps(state))
    except OSError as exc:
        print(f"warning: could not save state: {exc}", file=sys.stderr)


def list_apps(db_path: Path) -> None:
    with connect(db_path) as conn:
        rows = conn.execute(
            "SELECT app.identifier, COUNT(record.rec_id) AS n "
            "FROM app LEFT JOIN record ON record.app_id = app.app_id "
            "GROUP BY app.identifier ORDER BY n DESC"
        ).fetchall()
    print(f"{'notifications':>13}  bundle identifier")
    for identifier, count in rows:
        print(f"{count:>13}  {identifier}")


def fetch_new(db_path: Path, bundle_ids: list[str], after_id: int) -> list[tuple]:
    query = (
        "SELECT record.rec_id, app.identifier, record.data, record.delivered_date "
        "FROM record JOIN app ON app.app_id = record.app_id "
        "WHERE record.rec_id > ?"
    )
    params: list = [after_id]
    if bundle_ids:
        placeholders = ",".join("?" for _ in bundle_ids)
        query += f" AND app.identifier IN ({placeholders})"
        params.extend(bundle_ids)
    query += " ORDER BY record.rec_id"

    with connect(db_path) as conn:
        return conn.execute(query, params).fetchall()


def append_line(out_path: Path, line: str, header: str | None) -> None:
    exists = out_path.exists()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("a", encoding="utf-8") as handle:
        if not exists and header:
            handle.write(header + "\n")
        handle.write(line + "\n")


def process_once(args, state: dict) -> int:
    db_path = Path(args.db) if args.db else default_db_path()
    if not db_path or not db_path.exists():
        print("error: Notification Center database not found. Pass --db explicitly.", file=sys.stderr)
        return 0

    last_id = int(state.get("last_rec_id", 0))
    try:
        rows = fetch_new(db_path, args.bundle_id, last_id)
    except sqlite3.OperationalError as exc:
        print(f"error: cannot read the database ({exc}). Grant Full Disk Access "
              f"to your terminal in System Settings ▸ Privacy & Security.", file=sys.stderr)
        return 0

    written = 0
    out_path = Path(args.out).expanduser()

    for rec_id, identifier, blob, delivered in rows:
        state["last_rec_id"] = max(int(rec_id), int(state.get("last_rec_id", 0)))
        title, body = decode_record(blob)
        text = "\n".join(part for part in (title, body) if part)
        if not text:
            continue

        parsed = ep.parse(
            text,
            source=identifier,
            received_at=apple_time(delivered).astimezone(),
            default_currency=args.currency,
        )

        if parsed.kind not in ("expense", "credit"):
            if args.verbose:
                print(f"skip [{parsed.kind}:{parsed.reason}] {text[:70]!r}")
            continue

        line = ep.format_line(parsed, args.format)
        if args.dry_run:
            print(f"would log: {line}")
        else:
            append_line(out_path, line, ep.HEADERS.get(args.format))
            if args.verbose:
                print(f"logged: {line}")
        written += 1

    return written


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", help="Path to the Notification Center database (auto-detected by default).")
    parser.add_argument("--bundle-id", action="append", default=[],
                        help="Only log notifications from this app. Repeatable. Omit to watch everything.")
    parser.add_argument("--out", default="~/expenses.txt", help="Log file to append to.")
    parser.add_argument("--format", default="tsv", choices=["tsv", "csv", "jsonl", "plain"])
    parser.add_argument("--currency", default="GTQ", help="Assumed currency when a notification omits one.")
    parser.add_argument("--interval", type=float, default=15.0, help="Seconds between polls.")
    parser.add_argument("--state", default=str(DEFAULT_STATE), help="Where to remember the last record seen.")
    parser.add_argument("--once", action="store_true", help="Poll a single time and exit.")
    parser.add_argument("--dry-run", action="store_true", help="Print what would be logged, write nothing.")
    parser.add_argument("--list-apps", action="store_true", help="List app bundle identifiers seen, then exit.")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if sys.platform != "darwin":
        print("error: this bridge only runs on macOS.", file=sys.stderr)
        return 2

    if args.list_apps:
        db_path = Path(args.db) if args.db else default_db_path()
        if not db_path:
            print("error: Notification Center database not found.", file=sys.stderr)
            return 2
        list_apps(db_path)
        return 0

    state_path = Path(args.state).expanduser()
    state = load_state(state_path)

    # First run: start from the newest record so we do not import old history.
    if "last_rec_id" not in state:
        db_path = Path(args.db) if args.db else default_db_path()
        if db_path and db_path.exists():
            with connect(db_path) as conn:
                newest = conn.execute("SELECT COALESCE(MAX(rec_id), 0) FROM record").fetchone()[0]
            state["last_rec_id"] = int(newest)
            save_state(state_path, state)
            print(f"starting from record {newest}; new notifications only")

    try:
        while True:
            count = process_once(args, state)
            if not args.dry_run:
                save_state(state_path, state)
            if args.once:
                print(f"{count} notification(s) logged")
                return 0
            time.sleep(args.interval)
    except KeyboardInterrupt:
        save_state(state_path, state)
        print("\nstopped")
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
