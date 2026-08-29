#!/bin/bash
# Double-click this file in Finder to set up expense logging on this Mac.
# It asks a few questions and does the rest. Nothing is installed system-wide,
# and it never writes to any system file.

# macOS ships bash 3.2: no mapfile, and empty arrays trip "set -u".
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE="$SCRIPT_DIR/notification_bridge.py"
INSTALLER="$SCRIPT_DIR/install_launchagent.sh"
ICLOUD="$HOME/Library/Mobile Documents/com~apple~CloudDocs"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
dim()  { printf '\033[2m%s\033[0m\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
bad()  { printf '\033[31m✗\033[0m %s\n' "$1"; }
pause_and_exit() { echo; read -r -p "Press Return to close this window. " _; exit "${1:-0}"; }

clear
bold "Expense Logger — setup"
echo
echo "This sets up your Mac to watch your bank notifications and write every"
echo "purchase into a text file. It takes about five minutes."
echo
dim "You can close this window at any time and nothing will be left behind."
echo

# ---------------------------------------------------------------- python check
if ! command -v python3 >/dev/null 2>&1; then
    bad "Python is not installed yet."
    echo
    echo "macOS includes it, but only once the developer tools are added."
    echo "A window may pop up asking to install them — click Install, wait for"
    echo "it to finish, then double-click this file again."
    echo
    xcode-select --install 2>/dev/null || true
    pause_and_exit 1
fi
PYTHON="$(command -v python3)"
ok "Python found"

if [ ! -f "$BRIDGE" ]; then
    bad "Cannot find notification_bridge.py next to this file."
    echo "Keep this file inside the 'bridge' folder you downloaded."
    pause_and_exit 1
fi

# ------------------------------------------------------- full disk access test
echo
if ! "$PYTHON" "$BRIDGE" --list-apps >/dev/null 2>&1; then
    bad "This Mac will not let Terminal read your notifications yet."
    echo
    bold "Here is how to fix it — it takes a minute:"
    echo "  1. A Settings window is opening on Privacy & Security ▸ Full Disk Access."
    echo "  2. Find 'Terminal' in the list and switch it ON."
    echo "     If Terminal is not listed, click + , then press Command-Shift-G,"
    echo "     type  /System/Applications/Utilities  and pick Terminal."
    echo "  3. Quit Terminal completely (Command-Q) and double-click this file again."
    echo
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true
    pause_and_exit 1
fi
ok "Able to read notifications"

# ------------------------------------------------------------------ pick an app
echo
bold "Which app shows your bank notifications?"
echo
dim "Bank card alerts usually arrive through Apple Wallet, so the answer is"
dim "often 'Wallet'. Here are the apps that have sent you notifications:"
echo

APP_LIST="$("$PYTHON" "$BRIDGE" --list-apps 2>/dev/null | tail -n +2 | head -20)"

INDEX=0
APP_IDS=""
while IFS= read -r line; do
    [ -z "$line" ] && continue
    count="$(echo "$line" | awk '{print $1}')"
    id="$(echo "$line" | awk '{print $2}')"
    [ -z "$id" ] && continue
    INDEX=$((INDEX + 1))
    APP_IDS="$APP_IDS$id
"
    printf "  %2d) %-45s %s notifications\n" "$INDEX" "$id" "$count"
done <<EOF
$APP_LIST
EOF

if [ "$INDEX" -eq 0 ]; then
    bad "No notifications found at all."
    echo "Make sure iPhone Mirroring is connected and you have received a"
    echo "notification recently, then try again."
    pause_and_exit 1
fi

echo
read -r -p "Type the number of your bank's app and press Return: " CHOICE
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt "$INDEX" ]; then
    bad "That is not one of the numbers above. Run this again to retry."
    pause_and_exit 1
fi
BUNDLE_ID="$(printf '%s' "$APP_IDS" | sed -n "${CHOICE}p")"
ok "Watching $BUNDLE_ID"

# ------------------------------------------------------------- where to save it
echo
bold "Where should the file be saved?"
echo
if [ -d "$ICLOUD" ]; then
    OUT="$ICLOUD/expenses.txt"
    echo "  Saving to iCloud Drive, so you can open it on your iPhone too:"
    echo "  $OUT"
else
    OUT="$HOME/Documents/expenses.txt"
    dim "  iCloud Drive is not set up on this Mac, so using your Documents folder:"
    echo "  $OUT"
fi
echo
read -r -p "Press Return to accept, or type a different full path: " CUSTOM
[ -n "$CUSTOM" ] && OUT="$CUSTOM"

# -------------------------------------------------------------------- dry run
echo
bold "Checking what it would record…"
echo
"$PYTHON" "$BRIDGE" --bundle-id "$BUNDLE_ID" --once --dry-run --verbose 2>&1 | head -15
echo
dim "(Nothing has been saved yet. If the lines above look wrong, close this"
dim " window and say so — the reading rules can be adjusted.)"
echo
read -r -p "Start recording from now on? [Y/n] " CONFIRM
case "${CONFIRM:-y}" in
    [Nn]*) echo "Stopped. Nothing was installed."; pause_and_exit 0 ;;
esac

# --------------------------------------------------------------------- install
echo
bash "$INSTALLER" --bundle-id "$BUNDLE_ID" --out "$OUT" --currency GTQ || {
    bad "Could not set it to run automatically."
    pause_and_exit 1
}

echo
ok "Done. It is running now and will start again by itself after a restart."
echo
bold "What happens next"
echo "  • Buy something with your card. Within about 15 seconds the purchase"
echo "    is added to:"
echo "    $OUT"
echo "  • Open that file any time — on the Mac, or on your iPhone in the Files"
echo "    app under iCloud Drive."
echo
bold "One more thing you may need to do"
echo "  Because it now runs in the background, macOS treats it as a different"
echo "  program than Terminal. If nothing appears in the file after a purchase,"
echo "  add Python to Full Disk Access as well:"
echo
echo "    $PYTHON"
echo
if command -v pbcopy >/dev/null 2>&1; then
    printf '%s' "$PYTHON" | pbcopy
    dim "  (That path has been copied for you. In the Settings window: click + ,"
    dim "   press Command-Shift-G, paste, and press Return.)"
fi
echo
dim "To stop it later, run:  $INSTALLER --uninstall"
pause_and_exit 0
