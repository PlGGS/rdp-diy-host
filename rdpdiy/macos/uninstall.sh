#!/bin/sh
# Removes rdp.diy Host. Installed at /Applications/rdpdiy-host.app/Contents/Resources/uninstall.sh
#   sudo /Applications/rdpdiy-host.app/Contents/Resources/uninstall.sh
set -u
[ "$(id -u)" = 0 ] || { echo "Run as root (sudo)." >&2; exit 1; }
DAEMON=diy.rdp.rdpdiy-host_service
AGENT=diy.rdp.rdpdiy-host_server
for uid in $(ps -axo uid=,comm= | awk '$2 ~ /loginwindow$/ { print $1 }' | sort -u); do
	launchctl bootout "gui/$uid/$AGENT" 2>/dev/null || true
done
launchctl bootout "system/$DAEMON" 2>/dev/null || true
pkill -x rdpdiy-host 2>/dev/null || true
pkill -f '/rdpdiy-host.app/Contents/MacOS/service' 2>/dev/null || true
rm -f "/Library/LaunchDaemons/$DAEMON.plist" "/Library/LaunchAgents/$AGENT.plist" \
	/usr/local/bin/rdpdiy-host /var/log/rdpdiy-host_service.out /var/log/rdpdiy-host_service.err
rm -rf /Applications/rdpdiy-host.app
tccutil reset All diy.rdp.host >/dev/null 2>&1 || true
pkgutil --forget diy.rdp.host >/dev/null 2>&1 || true
# Keeps this computer's ID and settings (/var/root/Library/Preferences/diy.rdp.rdpdiy-host)
# unless --purge is given, so a reinstall shows up as the same device in the console.
if [ "${1:-}" = --purge ]; then
	rm -rf /var/root/Library/Preferences/diy.rdp.rdpdiy-host /var/root/Library/Logs/rdpdiy-host
	for home in /Users/*; do
		rm -rf "$home/Library/Preferences/diy.rdp.rdpdiy-host" "$home/Library/Logs/rdpdiy-host"
	done
fi
echo "rdp.diy Host removed."
