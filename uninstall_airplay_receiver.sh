#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="airplay-receiver"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CONFIG_FILE="/etc/default/${SERVICE_NAME}"
RUNNER="/usr/local/bin/${SERVICE_NAME}-run"
STARTER="/usr/local/bin/airplay-on"
STOPPER="/usr/local/bin/airplay-off"
STATUS="/usr/local/bin/airplay-status"
LOG_DIR="/var/log/${SERVICE_NAME}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run this uninstaller with sudo or as root."
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This uninstaller currently supports Debian/Raspberry Pi OS systems with apt."
  exit 1
fi

echo "Stopping AirPlay receiver service if running..."
systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true

echo "Removing service and helper files..."
rm -f "${SERVICE_FILE}"
rm -f "${CONFIG_FILE}"
rm -f "${RUNNER}"
rm -f "${STARTER}"
rm -f "${STOPPER}"
rm -f "${STATUS}"

systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

echo "Removing installed packages..."
apt-get remove -y uxplay avahi-utils
apt-get autoremove -y

echo
echo "UxPlay and the AirPlay receiver service have been removed."
echo
echo "Kept in place:"
echo "  - avahi-daemon"
echo "  - ${LOG_DIR} (if it existed)"
echo
echo "If you also want to remove Avahi completely, run:"
echo "  sudo apt-get remove -y avahi-daemon && sudo apt-get autoremove -y"
