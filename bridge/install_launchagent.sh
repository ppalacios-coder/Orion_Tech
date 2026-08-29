#!/bin/bash
# Install (or remove) a LaunchAgent that keeps the notification bridge running.
#
# The bridge only sees notifications while the Mac is awake and iPhone Mirroring
# is connected, but a LaunchAgent means it is always running when it can be,
# and restarts after a reboot.
#
#   ./install_launchagent.sh --bundle-id com.apple.Passbook \
#       --out "$HOME/Library/Mobile Documents/com~apple~CloudDocs/expenses.txt"
#   ./install_launchagent.sh --uninstall

set -euo pipefail

LABEL="com.expenselogger.bridge"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/Library/Logs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE="$SCRIPT_DIR/notification_bridge.py"

BUNDLE_IDS=()
OUT="$HOME/Library/Mobile Documents/com~apple~CloudDocs/expenses.txt"
CURRENCY="GTQ"
FORMAT="tsv"
INTERVAL="15"
UNINSTALL=0

while [ $# -gt 0 ]; do
    case "$1" in
        --bundle-id) BUNDLE_IDS+=("$2"); shift 2 ;;
        --out)       OUT="$2"; shift 2 ;;
        --currency)  CURRENCY="$2"; shift 2 ;;
        --format)    FORMAT="$2"; shift 2 ;;
        --interval)  INTERVAL="$2"; shift 2 ;;
        --uninstall) UNINSTALL=1; shift ;;
        -h|--help)   sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

unload_if_present() {
    if launchctl print "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then
        launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    fi
}

if [ "$UNINSTALL" -eq 1 ]; then
    unload_if_present
    rm -f "$PLIST"
    echo "removed $LABEL"
    exit 0
fi

if [ ! -f "$BRIDGE" ]; then
    echo "error: cannot find $BRIDGE" >&2
    exit 1
fi

if [ ${#BUNDLE_IDS[@]} -eq 0 ]; then
    echo "error: pass at least one --bundle-id (find yours with:" >&2
    echo "       python3 \"$BRIDGE\" --list-apps)" >&2
    exit 2
fi

# XML-escape a value for the plist.
esc() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }

PYTHON="$(command -v python3)"
mkdir -p "$(dirname "$PLIST")" "$LOG_DIR"

{
    cat <<HEADER
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$(esc "$LABEL")</string>
	<key>ProgramArguments</key>
	<array>
		<string>$(esc "$PYTHON")</string>
		<string>$(esc "$BRIDGE")</string>
		<string>--out</string>
		<string>$(esc "$OUT")</string>
		<string>--currency</string>
		<string>$(esc "$CURRENCY")</string>
		<string>--format</string>
		<string>$(esc "$FORMAT")</string>
		<string>--interval</string>
		<string>$(esc "$INTERVAL")</string>
HEADER
    for id in "${BUNDLE_IDS[@]}"; do
        printf '\t\t<string>--bundle-id</string>\n\t\t<string>%s</string>\n' "$(esc "$id")"
    done
    cat <<FOOTER
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<true/>
	<key>StandardOutPath</key>
	<string>$(esc "$LOG_DIR/expense-logger-bridge.log")</string>
	<key>StandardErrorPath</key>
	<string>$(esc "$LOG_DIR/expense-logger-bridge.log")</string>
</dict>
</plist>
FOOTER
} > "$PLIST"

plutil -lint "$PLIST" >/dev/null

unload_if_present
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "installed $LABEL"
echo "  writes  : $OUT"
echo "  watching: ${BUNDLE_IDS[*]}"
echo "  log     : $LOG_DIR/expense-logger-bridge.log"
echo
echo "The terminal running it needs Full Disk Access — and so does launchd's copy."
echo "If the log shows 'cannot read the database', grant Full Disk Access to"
echo "$PYTHON in System Settings ▸ Privacy & Security ▸ Full Disk Access."
echo
echo "Check it:   launchctl print gui/$(id -u)/$LABEL | head -20"
echo "Remove it:  $0 --uninstall"
