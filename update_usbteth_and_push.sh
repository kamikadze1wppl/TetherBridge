#!/usr/bin/env bash
set -euo pipefail

########################################
# Configuration
########################################
LOCAL_SCRIPT="$HOME/usbteth.sh"
REMOTE_SCRIPT="/data/local/tmp/setup_forwarding.sh"

########################################
# Helpers
########################################
log() {
  printf '[INFO] %s\n' "$*" >&2
}

err() {
  printf '[ERROR] %s\n' "$*" >&2
}

die() {
  err "$@"
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found in PATH."
}

########################################
# Pre-flight checks
########################################
require_cmd ip
require_cmd sed
require_cmd adb

[ -f "$LOCAL_SCRIPT" ] || die "Local script not found: $LOCAL_SCRIPT"

########################################
# Auto-detect active internet interface
########################################
log "Detecting active internet interface..."

IFACE="$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if ($i=="dev") print $(i+1)}' | head -n1)"

if [ -z "$IFACE" ]; then
  die "Could not detect active internet interface (no route to 8.8.8.8?)."
fi

log "Active interface detected: $IFACE"

########################################
# Get IPv4 address of that interface
########################################
log "Detecting IPv4 address for interface: $IFACE"

IF_IP="$(ip -4 addr show dev "$IFACE" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1 || true)"

if [ -z "$IF_IP" ]; then
  die "No IPv4 address found on interface '$IFACE'. Is it up and configured?"
fi

if ! printf '%s\n' "$IF_IP" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
  die "Invalid IPv4 address detected: $IF_IP"
fi

log "Detected IP address: $IF_IP"

########################################
# Backup and patch $HOME/usbteth.sh
########################################
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="${LOCAL_SCRIPT}.bak.${TS}"

log "Creating backup: $BACKUP"
cp -- "$LOCAL_SCRIPT" "$BACKUP"

TMP_FILE="${LOCAL_SCRIPT}.tmp.$$"

log "Updating --to-destination in $LOCAL_SCRIPT"

# Replace the IP after --to-destination with the detected IF_IP
sed -E "s/(--to-destination)[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/\1 $IF_IP/g" \
  "$LOCAL_SCRIPT" > "$TMP_FILE"

if ! diff -q "$LOCAL_SCRIPT" "$TMP_FILE" >/dev/null 2>&1; then
  mv -- "$TMP_FILE" "$LOCAL_SCRIPT"
  log "Script updated to use TARGET_IP=$IF_IP."
else
  rm -f -- "$TMP_FILE"
  log "No changes needed (script already uses $IF_IP)."
fi

########################################
# ADB: check device and switch to root
########################################
log "Checking ADB connection…"

ADB_DEVICES_OUTPUT="$(adb devices | sed '1d' | grep -v '^\s*$' || true)"
if [ -z "$ADB_DEVICES_OUTPUT" ]; then
  die "No ADB device detected. Connect your device and ensure 'adb devices' lists it."
fi

log "ADB devices:"
printf '%s\n' "$ADB_DEVICES_OUTPUT"

log "Restarting adbd as root (adb root)…"
if ! adb root >/dev/null 2>&1; then
  die "Failed to run 'adb root'. Device may not support root via ADB."
fi

sleep 2

STATE="$(adb get-state 2>/dev/null || true)"
[ "$STATE" = "device" ] || die "Device is not in 'device' state after 'adb root' (state: '$STATE')."

########################################
# Push and execute script on device
########################################
log "Removing old remote script (if exists): $REMOTE_SCRIPT"
adb shell "rm -f '$REMOTE_SCRIPT'" || die "Failed to remove old remote script."

log "Pushing updated script to device: $REMOTE_SCRIPT"
adb push "$LOCAL_SCRIPT" "$REMOTE_SCRIPT" >/dev/null 2>&1 || die "Failed to push script via adb."

log "Setting executable bit on remote script."
adb shell "chmod +x '$REMOTE_SCRIPT'" || die "Failed to chmod remote script."

log "Executing remote script via bash."
if adb shell "bash '$REMOTE_SCRIPT'"; then
  log "Remote script executed successfully."
else
  die "Remote script execution failed. Check device logs (logcat/dmesg) for details."
fi

log "All done. Interface=$IFACE, IP=$IF_IP, local_script=$LOCAL_SCRIPT, remote_script=$REMOTE_SCRIPT"
