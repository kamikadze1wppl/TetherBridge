#!/system/bin/sh
# Configure DNAT + forwarding on Android for USB-tethered PC

# --- Safety: stop on first error ---
set -e

log() {
  echo "[usbteth] $*" >&2
}

die() {
  log "ERROR: $*"
  exit 1
}

# --- Sanity: must be root ---
if [ "$(id -u)" != "0" ]; then
  die "This script must be run as root."
fi

# --- Parameters (can be overridden via env/adb) ---
# TARGET_IP is the IP of the PC on the USB tether interface.
TARGET_IP="${TARGET_IP:-10.160.10.60}"

# Allow overriding via WIFI_IFACE / USB_IFACE env vars.
WIFI_IFACE="${WIFI_IFACE:-}"
USB_IFACE="${USB_IFACE:-}"

# --- Auto-detect interfaces if not provided ---
# Try to find a Wi-Fi-style interface (wlan*, wifi*)
if [ -z "$WIFI_IFACE" ]; then
  WIFI_IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '/wlan|wifi/ {print $2; exit}')"
fi

# Try to find a USB-tether-style interface (rndis*, usb*)
if [ -z "$USB_IFACE" ]; then
  USB_IFACE="$(ip -o link show 2>/dev/null | awk -F': ' '/rndis|usb/ {print $2; exit}')"
fi

[ -n "$WIFI_IFACE" ] || die "Could not auto-detect WIFI_IFACE (no wlan*/wifi* link found)."
[ -n "$USB_IFACE" ]  || die "Could not auto-detect USB_IFACE (no rndis*/usb* link found)."

# Verify interfaces actually exist
ip link show "$WIFI_IFACE" >/dev/null 2>&1 || die "Interface '$WIFI_IFACE' not found."
ip link show "$USB_IFACE"  >/dev/null 2>&1 || die "Interface '$USB_IFACE' not found."

log "Using WIFI_IFACE='$WIFI_IFACE', USB_IFACE='$USB_IFACE', TARGET_IP='$TARGET_IP'"

# --- Basic sanity: TARGET_IP looks like IPv4 ---
case "$TARGET_IP" in
  (*.*.*.*)
    ;;
  (*)
    die "TARGET_IP '$TARGET_IP' does not look like an IPv4 address."
    ;;
esac

# --- Enable IP forwarding safely ---
IPFWD_PATH="/proc/sys/net/ipv4/ip_forward"
if [ -w "$IPFWD_PATH" ]; then
  CURRENT_FWD="$(cat "$IPFWD_PATH" 2>/dev/null || echo 0)"
  if [ "$CURRENT_FWD" != "1" ]; then
    log "Enabling IPv4 forwarding"
    echo 1 > "$IPFWD_PATH"
  else
    log "IPv4 forwarding already enabled"
  fi
else
  die "Cannot write $IPFWD_PATH (no permission?)."
fi

# --- Helpers to make iptables rules idempotent ---
ensure_rule() {
  # $1... = iptables arguments
  if iptables -C "$@" 2>/dev/null; then
    log "Rule already exists: iptables -C $*"
  else
    log "Inserting rule: iptables -I $*"
    iptables -I "$@"
  fi
}

delete_rule_if_exists() {
  # $1... = iptables arguments
  if iptables -C "$@" 2>/dev/null; then
    log "Deleting rule: iptables -D $*"
    iptables -D "$@"
  fi
}

# --- Optional "clean" mode: remove our rules and exit ---
if [ "${1:-}" = "clean" ]; then
  log "Running in CLEAN mode – removing rules."

  delete_rule_if_exists nat PREROUTING -i "$WIFI_IFACE" -p tcp -j DNAT --to-destination "$TARGET_IP"
  delete_rule_if_exists nat PREROUTING -i "$WIFI_IFACE" -p udp -j DNAT --to-destination "$TARGET_IP"

  delete_rule_if_exists tetherctrl_FORWARD -i "$WIFI_IFACE" -o "$USB_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
  delete_rule_if_exists tetherctrl_FORWARD -i "$USB_IFACE"  -o "$WIFI_IFACE" -j ACCEPT
  delete_rule_if_exists tetherctrl_FORWARD -i "$WIFI_IFACE" -o "$USB_IFACE" -p tcp -j ACCEPT
  delete_rule_if_exists tetherctrl_FORWARD -i "$WIFI_IFACE" -o "$USB_IFACE" -p udp -j ACCEPT

  log "Clean mode completed."
  exit 0
fi

# --- Add DNAT rules (Wi-Fi -> PC on USB) ---
ensure_rule nat PREROUTING -i "$WIFI_IFACE" -p tcp -j DNAT --to-destination "$TARGET_IP"
ensure_rule nat PREROUTING -i "$WIFI_IFACE" -p udp -j DNAT --to-destination "$TARGET_IP"

# --- Add FORWARD rules in tetherctrl_FORWARD chain ---
ensure_rule tetherctrl_FORWARD -i "$WIFI_IFACE" -o "$USB_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
ensure_rule tetherctrl_FORWARD -i "$USB_IFACE"  -o "$WIFI_IFACE" -j ACCEPT
ensure_rule tetherctrl_FORWARD -i "$WIFI_IFACE" -o "$USB_IFACE" -p tcp -j ACCEPT
ensure_rule tetherctrl_FORWARD -i "$WIFI_IFACE" -o "$USB_IFACE" -p udp -j ACCEPT

log "Rules applied successfully."

# --- Short summary for debugging ---
log "Current nat PREROUTING DNAT entries:"
iptables -t nat -L PREROUTING -n | grep DNAT || log "No DNAT lines found in PREROUTING."

log "Current tetherctrl_FORWARD entries (first 20 lines):"
iptables -L tetherctrl_FORWARD -n | head -n 20 || log "tetherctrl_FORWARD chain not found?"
