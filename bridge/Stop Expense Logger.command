#!/bin/bash
# Double-click this file to stop expense logging and remove the background
# service. Your expenses.txt file is left exactly where it is.

set -o pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

clear
printf '\033[1m%s\033[0m\n\n' "Expense Logger — stop"
echo "This stops the background service that records your purchases."
echo "Your expenses.txt file is not touched or deleted."
echo
read -r -p "Stop it? [y/N] " ANSWER
case "${ANSWER:-n}" in
    [Yy]*) ;;
    *) echo "Nothing changed."; read -r -p "Press Return to close. " _; exit 0 ;;
esac

echo
bash "$SCRIPT_DIR/install_launchagent.sh" --uninstall
echo
printf '\033[32m✓\033[0m %s\n' "Stopped. Nothing is running any more."
echo
echo "To start it again, double-click 'Setup Expense Logger.command'."
echo
read -r -p "Press Return to close this window. " _
