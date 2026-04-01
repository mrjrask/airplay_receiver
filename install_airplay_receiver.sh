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
LOG_FILE="${LOG_DIR}/${SERVICE_NAME}.log"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run this installer with sudo or as root."
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This installer currently supports Debian/Raspberry Pi OS systems with apt."
  exit 1
fi

PI_USER="${SUDO_USER:-$(logname 2>/dev/null || true)}"
if [[ -z "${PI_USER}" || "${PI_USER}" == "root" ]]; then
  PI_USER="pi"
fi

if ! id "${PI_USER}" >/dev/null 2>&1; then
  echo "User '${PI_USER}' does not exist. Edit the installer or create the user first."
  exit 1
fi

ARCH="$(dpkg --print-architecture)"
HOSTNAME_NOW="$(hostname)"

echo "Updating package lists..."
apt-get update

echo "Installing required packages..."
apt-get install -y \
  uxplay \
  avahi-daemon \
  avahi-utils \
  gstreamer1.0-tools

mkdir -p "${LOG_DIR}"
touch "${LOG_FILE}"
chown "${PI_USER}:${PI_USER}" "${LOG_FILE}"

cat > "${CONFIG_FILE}" <<EOF
# AirPlay receiver configuration
# Edit this file if you want to rename the receiver or adjust options.

# Name shown on Apple devices
AIRPLAY_NAME="${HOSTNAME_NOW} AirPlay"

# Auto-detect display mode:
#   auto      -> chooses waylandsink, glimagesink, or kmssink
#   wayland   -> force waylandsink
#   x11       -> force glimagesink
#   kms       -> force kmssink
DISPLAY_MODE="auto"

# Set to 1 to force software H.264 decoding if you have video issues
FORCE_SOFTWARE_DECODE="0"

# Extra raw uxplay flags, for example:
#   EXTRA_OPTS="-fullscreen"
#   EXTRA_OPTS="-bt709"
EXTRA_OPTS=""

# Audio output:
# leave blank to use system default, or set a GStreamer sink if needed.
# Example:
#   AUDIO_SINK="alsasink"
AUDIO_SINK=""
EOF

cat > "${RUNNER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/default/airplay-receiver"
LOG_FILE="/var/log/airplay-receiver/airplay-receiver.log"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1091
  source "${CONFIG_FILE}"
fi

AIRPLAY_NAME="${AIRPLAY_NAME:-Raspberry Pi AirPlay}"
DISPLAY_MODE="${DISPLAY_MODE:-auto}"
FORCE_SOFTWARE_DECODE="${FORCE_SOFTWARE_DECODE:-0}"
EXTRA_OPTS="${EXTRA_OPTS:-}"
AUDIO_SINK="${AUDIO_SINK:-}"

choose_video_sink() {
  case "${DISPLAY_MODE}" in
    wayland)
      echo "waylandsink"
      return
      ;;
    x11)
      echo "glimagesink"
      return
      ;;
    kms)
      echo "kmssink"
      return
      ;;
    auto)
      ;;
    *)
      echo "kmssink"
      return
      ;;
  esac

  if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    echo "waylandsink"
  elif [[ -n "${DISPLAY:-}" ]]; then
    echo "glimagesink"
  else
    echo "kmssink"
  fi
}

VIDEO_SINK="$(choose_video_sink)"

OPTS=()
OPTS+=("-nh")
OPTS+=("-n" "${AIRPLAY_NAME}")
OPTS+=("-vs" "${VIDEO_SINK}")

if [[ "${FORCE_SOFTWARE_DECODE}" == "1" ]]; then
  OPTS+=("-avdec")
fi

if [[ -n "${AUDIO_SINK}" ]]; then
  OPTS+=("-as" "${AUDIO_SINK}")
fi

if [[ -n "${EXTRA_OPTS}" ]]; then
  # Intentional word splitting for raw flags from config
  # shellcheck disable=SC2206
  EXTRA_ARRAY=( ${EXTRA_OPTS} )
  OPTS+=("${EXTRA_ARRAY[@]}")
fi

mkdir -p "$(dirname "${LOG_FILE}")"

{
  echo "============================================================"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting airplay-receiver"
  echo "Using AirPlay name: ${AIRPLAY_NAME}"
  echo "Using video sink: ${VIDEO_SINK}"
  echo "Force software decode: ${FORCE_SOFTWARE_DECODE}"
  echo "Extra options: ${EXTRA_OPTS}"
} >> "${LOG_FILE}"

exec uxplay "${OPTS[@]}" >> "${LOG_FILE}" 2>&1
EOF

chmod 755 "${RUNNER}"

cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=On-demand AirPlay receiver (UxPlay)
After=network-online.target avahi-daemon.service sound.target
Wants=network-online.target avahi-daemon.service

[Service]
Type=simple
User=${PI_USER}
Group=${PI_USER}
Environment=HOME=/home/${PI_USER}
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u "${PI_USER}")
ExecStart=${RUNNER}
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

cat > "${STARTER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sudo systemctl start avahi-daemon
sudo systemctl start airplay-receiver.service
sudo systemctl --no-pager --full status airplay-receiver.service
EOF

cat > "${STOPPER}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sudo systemctl stop airplay-receiver.service
echo "AirPlay receiver stopped."
EOF

cat > "${STATUS}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sudo systemctl --no-pager --full status airplay-receiver.service
EOF

chmod 755 "${STARTER}" "${STOPPER}" "${STATUS}"

systemctl daemon-reload
systemctl enable avahi-daemon >/dev/null 2>&1 || true
systemctl enable "${SERVICE_NAME}.service"
systemctl restart avahi-daemon

echo
echo "Installation complete."
echo
echo "Installed:"
echo "  - UxPlay"
echo "  - avahi-daemon"
echo "  - ${SERVICE_FILE}"
echo "  - ${CONFIG_FILE}"
echo "  - ${RUNNER}"
echo "  - ${STARTER}"
echo "  - ${STOPPER}"
echo "  - ${STATUS}"
echo
echo "The AirPlay receiver is installed ON-DEMAND and auto-starts at boot."
echo
echo "To start it when needed:"
echo "  airplay-on"
echo "  (it is also enabled to start automatically on boot)"
echo
echo "To stop it:"
echo "  airplay-off"
echo
echo "To check status:"
echo "  airplay-status"
echo
echo "To change the advertised AirPlay name or tweak options:"
echo "  sudo nano ${CONFIG_FILE}"
echo
echo "Notes:"
echo "  - On Raspberry Pi OS Lite, kmssink is usually the correct display path."
echo "  - If devices do not see the receiver, verify both devices are on the same LAN/Wi-Fi and Avahi is running."
echo "  - If video is unstable, set FORCE_SOFTWARE_DECODE=\"1\" in ${CONFIG_FILE}"
