# TetherBridge -ROOT ONLY
Advanced USB Tethering and iptables Port Forwarding on Rooted Android: Enabling LAN Access to Linux PC Services via the Android Device's IP.

* **Script 1: `usbteth.sh` (Android / Device-side forwarding script)**

  * Enables kernel IPv4 forwarding to allow packet routing between interfaces.
  * Inserts high-priority `iptables` DNAT rules in the `nat` table to redirect all TCP and UDP traffic arriving on `wlan0` to a specific target IP.
  * Adds permissive forwarding rules inside Android’s `tetherctrl_FORWARD` chain to allow bidirectional traffic between:

    * `wlan0` (Wi-Fi side)
    * `rndis0` (USB tethering interface)
  * Uses rule insertion at the top of chains to ensure its rules take precedence over existing Android tethering and firewall rules.
  * Designed to dynamically forward traffic from Wi-Fi → USB and USB → Wi-Fi for transparent routing through the Android device.
  * Supports quick reconfiguration simply by changing the target IP, without modifying the rest of the networking logic.

* **Script 2: `update_usbteth_and_push.sh` (Linux / PC-side automation script)**

  * Automatically detects the active Internet-providing network interface by querying the routing table (default route logic).
  * Dynamically extracts the current IPv4 address assigned to that interface.
  * Creates timestamped backups of `$HOME/usbteth.sh` before any modification to ensure rollback safety.
  * Safely edits the Android-side script by replacing the `--to-destination` IP values with the newly detected host IP.
  * Validates required tools (`ip`, `sed`, `adb`) before running to prevent runtime failures.
  * Manages the full Android deployment lifecycle through ADB:

    * Restarts ADB daemon as root.
    * Removes any stale remote forwarding script.
    * Pushes the updated script to the device.
    * Applies executable permissions.
    * Executes the script directly on the Android device.
  * Designed for repeatable, one-command execution to keep forwarding rules synchronized with dynamic IP changes.
  * Eliminates manual errors by automating environment detection, script patching, and remote execution.

* **Forward-looking advantages of this setup**

  * Enables near real-time reconfiguration of tethering and forwarding as network topology changes.
  * Reduces human error by making all IP and interface selection logic automatic.
  * Provides a foundation for future automation such as:

    * Hotplug-based triggers (udev / systemd).
    * Live interface change monitoring.
    * Self-healing networking when links flap or devices reconnect.
