#!/bin/bash
# Double-click this file in Finder to add a bank statement to your expense file.
# macOS ships bash 3.2, so no mapfile and no "set -u".

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMPORTER="$SCRIPT_DIR/import_statement.py"
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
CONFIG="$HOME/.expense-logger-importer"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
dim()  { printf '\033[2m%s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '\033[31m✗\033[0m %s\n' "$1"; }
finish() { echo; read -r -p "Press Return to close this window. " _; exit "${1:-0}"; }

clear
bold "Add a bank statement to your expense file"
echo
echo "Download your statement from Bi en Línea first — Excel or CSV if it offers"
echo "a choice. Then come back here."
echo

if ! command -v python3 >/dev/null 2>&1; then
    bad "Python is not installed yet."
    echo "A window may appear offering to install developer tools. Click Install,"
    echo "wait for it to finish, then double-click this file again."
    xcode-select --install 2>/dev/null || true
    finish 1
fi

if [ ! -f "$IMPORTER" ]; then
    bad "Cannot find import_statement.py next to this file."
    echo "Keep this file inside the 'importer' folder you downloaded."
    finish 1
fi

# ------------------------------------------------------------- pick a statement
bold "Which file?"
echo
dim "The most recent spreadsheets in your Downloads folder:"
echo

FILES=""
COUNT=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    COUNT=$((COUNT + 1))
    FILES="$FILES$f
"
    printf "  %2d) %s\n" "$COUNT" "$(basename "$f")"
done <<EOF
$(ls -t "$HOME"/Downloads/*.xlsx "$HOME"/Downloads/*.csv "$HOME"/Downloads/*.tsv 2>/dev/null | head -10)
EOF

if [ "$COUNT" -eq 0 ]; then
    dim "  (nothing found in Downloads)"
fi
echo
echo "Or drag the file from Finder into this window and press Return."
echo
read -r -p "Number, or dragged file: " CHOICE

if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$COUNT" ]; then
    STATEMENT="$(printf '%s' "$FILES" | sed -n "${CHOICE}p")"
else
    # A dragged file arrives quoted and/or backslash-escaped.
    STATEMENT="$(printf '%s' "$CHOICE" | sed -e "s/^'//" -e "s/'$//" -e 's/\\ / /g')"
fi

if [ ! -f "$STATEMENT" ]; then
    bad "Cannot find that file: $STATEMENT"
    finish 1
fi
ok "Reading $(basename "$STATEMENT")"

# ------------------------------------------------------- where the master lives
OUT=""
[ -f "$CONFIG" ] && OUT="$(cat "$CONFIG")"

if [ -n "$OUT" ] && [ -d "$(dirname "$OUT")" ]; then
    dim "Adding to $OUT"
else
    echo
    bold "Where should your expense file live?"
    echo
    LOCATIONS=""
    LOC_COUNT=0
    add_location() {
        [ -d "$1" ] || return 0
        LOC_COUNT=$((LOC_COUNT + 1))
        LOCATIONS="$LOCATIONS$1
"
        printf "  %2d) %s\n" "$LOC_COUNT" "$2"
    }
    for gd in "$HOME"/Library/CloudStorage/GoogleDrive-*/My\ Drive; do
        add_location "$gd" "Google Drive  ($(basename "$(dirname "$gd")" | sed 's/GoogleDrive-//'))"
    done
    add_location "/Volumes/GoogleDrive/My Drive" "Google Drive  (older setup)"
    add_location "$HOME/Google Drive"            "Google Drive  (older setup)"
    add_location "$ICLOUD"                       "iCloud Drive"
    add_location "$HOME/Documents"               "Documents folder on this Mac"

    echo
    read -r -p "Type a number: " LOC_CHOICE
    if [[ "$LOC_CHOICE" =~ ^[0-9]+$ ]] && [ "$LOC_CHOICE" -ge 1 ] && [ "$LOC_CHOICE" -le "$LOC_COUNT" ]; then
        OUT="$(printf '%s' "$LOCATIONS" | sed -n "${LOC_CHOICE}p")/expenses.csv"
    else
        OUT="$HOME/Documents/expenses.csv"
    fi
    printf '%s' "$OUT" > "$CONFIG"
    ok "Using $OUT"
fi

# -------------------------------------------------------------------- preview
echo
bold "Checking the file…"
echo
if ! python3 "$IMPORTER" "$STATEMENT" --out "$OUT" --dry-run --verbose; then
    echo
    bad "That file could not be read."
    echo
    echo "Send me the message above along with the first few rows of the file,"
    echo "and I will teach it this layout. This is normal the first time."
    finish 1
fi

echo
read -r -p "Add these to your expense file? [Y/n] " CONFIRM
case "${CONFIRM:-y}" in
    [Nn]*) echo "Nothing added."; finish 0 ;;
esac

echo
python3 "$IMPORTER" "$STATEMENT" --out "$OUT" || { bad "Something went wrong."; finish 1; }

echo
ok "Done."
echo
echo "Your expense file: $OUT"
echo "Open it by double-clicking — it opens in Numbers or Excel, and in Google"
echo "Sheets once Drive syncs it."
echo
dim "Next month, download the new statement and double-click this file again."
dim "Anything already imported is skipped, so overlapping statements are safe."
finish 0
