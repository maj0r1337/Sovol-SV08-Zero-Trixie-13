#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Sovol SV08 / CB1
# CAN Configuration for Debian/Armbian 13
#
# Included:
# - systemd-networkd configuration for can0
# - CAN bitrate 1,000,000
# - TxQueueLength 128
# - Fallback service for txqueuelen
# - Clean unloading of gs_usb before reboot/shutdown
# ============================================================

CAN_INTERFACE="can0"
CAN_BITRATE="1000000"
CAN_QUEUE_LENGTH="128"

NETWORK_FILE="/etc/systemd/network/80-can0.network"
QUEUE_SCRIPT="/usr/local/sbin/set-can0-queue.sh"
QUEUE_SERVICE="/etc/systemd/system/set-can0-queue.service"

SHUTDOWN_SCRIPT="/usr/local/bin/disconnect-can.sh"
SHUTDOWN_SERVICE="/etc/systemd/system/can-shutdown.service"

BACKUP_DIR="/root/sv08-can-backups/$(date +%Y%m%d-%H%M%S)"

# Standard ist Englisch. Nur wenn die Sprache mit 'de' beginnt, wird Deutsch genutzt.
IS_GERMAN=false
if [[ "${LANG:-}" =~ ^de ]]; then
    IS_GERMAN=true
fi

log() {
    local msg_en="$1"
    local msg_de="${2:-$1}" # Falls keine deutsche Version übergeben wurde, nimm die englische
    echo
    if [ "$IS_GERMAN" = true ]; then
        echo "==> $msg_de"
    else
        echo "==> $msg_en"
    fi
}

error() {
    local msg_en="$1"
    local msg_de="${2:-$1}"
    echo >&2
    if [ "$IS_GERMAN" = true ]; then
        echo "FEHLER: $msg_de" >&2
    else
        echo "ERROR: $msg_en" >&2
    fi
    exit 1
}

backup_file() {
    local file="$1"

    if [[ -e "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$file" "$BACKUP_DIR/"
        if [ "$IS_GERMAN" = true ]; then
            echo "Backup erstellt: $BACKUP_DIR/$(basename "$file")"
        else
            echo "Backup created: $BACKUP_DIR/$(basename "$file")"
        fi
    fi
}

if [[ "${EUID}" -ne 0 ]]; then
    error "This script must be run with sudo:
sudo $0" \
          "Dieses Skript muss mit sudo ausgeführt werden:
sudo $0"
fi

# ============================================================
# Check if the script has already been executed
# ============================================================
if [[ -e "$NETWORK_FILE" || -e "$QUEUE_SCRIPT" || -e "$QUEUE_SERVICE" || -e "$SHUTDOWN_SCRIPT" || -e "$SHUTDOWN_SERVICE" ]]; then
    echo
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    if [ "$IS_GERMAN" = true ]; then
        echo "Das Skript wurde bereits ausgeführt und muss nicht noch einmal ausgeführt werden."
        echo "Die Konfigurationsdateien sind bereits vorhanden."
    else
        echo "This script has already been executed and does not need to be run again."
        echo "The configuration files already exist."
    fi
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo
    exit 0
fi

log "Checking required programs" "Prüfe benötigte Programme"

for command in ip systemctl modprobe; do
    if ! command -v "$command" >/dev/null 2>&1; then
        error "Required program not found: $command" \
              "Benötigtes Programm nicht gefunden: $command"
    fi
done

log "Creating backup directory" "Erstelle Backup-Verzeichnis"

mkdir -p "$BACKUP_DIR"

log "Backing up existing configuration files" "Sichere vorhandene Konfigurationsdateien"

backup_file "$NETWORK_FILE"
backup_file "$QUEUE_SCRIPT"
backup_file "$QUEUE_SERVICE"
backup_file "$SHUTDOWN_SCRIPT"
backup_file "$SHUTDOWN_SERVICE"

log "Creating systemd-networkd configuration" "Erstelle systemd-networkd-Konfiguration"

mkdir -p /etc/systemd/network

cat > "$NETWORK_FILE" <<EOF
[Match]
Name=$CAN_INTERFACE

[Link]
TxQueueLength=$CAN_QUEUE_LENGTH

[Network]
CAN=true

[CAN]
BitRate=$CAN_BITRATE
EOF

chmod 644 "$NETWORK_FILE"

log "Creating CAN queue fallback script" "Erstelle CAN-Queue-Fallback-Skript"

cat > "$QUEUE_SCRIPT" <<'EOF'
#!/usr/bin/env bash

set -u

CAN_INTERFACE="can0"
QUEUE_LENGTH="128"
IP_BIN="$(command -v ip)"

# Wait until the USB CAN interface is available
for attempt in {1..30}; do
    if "$IP_BIN" link show "$CAN_INTERFACE" >/dev/null 2>&1; then
        "$IP_BIN" link set "$CAN_INTERFACE" txqueuelen "$QUEUE_LENGTH"

        CURRENT_QUEUE="$("$IP_BIN" -details link show "$CAN_INTERFACE" \
            | sed -n 's/.*qlen \([0-9]*\).*/\1/p')"

        if [[ "$CURRENT_QUEUE" == "$QUEUE_LENGTH" ]]; then
            echo "$CAN_INTERFACE: txqueuelen=$CURRENT_QUEUE"
            exit 0
        fi

        echo "Error: could not set txqueuelen. / Fehler: txqueuelen konnte nicht gesetzt werden." >&2
        exit 1
    fi

    sleep 1
done

echo "$CAN_INTERFACE not found within 30 seconds. / $CAN_INTERFACE wurde innerhalb von 30 Sekunden nicht gefunden." >&2
exit 1
EOF

chmod 755 "$QUEUE_SCRIPT"

log "Creating systemd service for CAN queue" "Erstelle systemd-Service für CAN-Queue"

cat > "$QUEUE_SERVICE" <<EOF
[Unit]
Description=Set CAN0 transmit queue length
After=systemd-networkd.service network-online.target
Wants=systemd-networkd.service network-online.target
Before=klipper.service

[Service]
Type=oneshot
ExecStart=$QUEUE_SCRIPT
RemainAfterExit=yes
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$QUEUE_SERVICE"

log "Creating clean shutdown script" "Erstelle Clean-Shutdown-Skript"

cat > "$SHUTDOWN_SCRIPT" <<'EOF'
#!/bin/sh

if /usr/sbin/ip link show can0 >/dev/null 2>&1; then
    /usr/sbin/ip link set can0 down || true
    /sbin/modprobe -r gs_usb || true
fi

exit 0
EOF

chmod 755 "$SHUTDOWN_SCRIPT"

log "Creating clean shutdown service" "Erstelle Clean-Shutdown-Service"

cat > "$SHUTDOWN_SERVICE" <<EOF
[Unit]
Description=Clean CAN-Bus disconnect before reboot
After=klipper.service systemd-networkd.service
Conflicts=shutdown.target
Before=shutdown.target reboot.target halt.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=$SHUTDOWN_SCRIPT
TimeoutStopSec=10

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SHUTDOWN_SERVICE"

log "Enabling systemd-networkd" "Aktiviere systemd-networkd"

systemctl enable systemd-networkd.service

log "Reloading systemd configuration" "Lade systemd-Konfiguration neu"

systemctl daemon-reload

log "Enabling CAN services" "Aktiviere CAN-Services"

systemctl enable "$QUEUE_SERVICE"
systemctl enable "$SHUTDOWN_SERVICE"

log "Restarting systemd-networkd" "Starte systemd-networkd neu"

systemctl restart systemd-networkd.service

log "Waiting for CAN interface" "Warte auf CAN-Interface"

CAN_FOUND="false"

for attempt in {1..30}; do
    if ip link show "$CAN_INTERFACE" >/dev/null 2>&1; then
        CAN_FOUND="true"
        break
    fi

    sleep 1
done

if [[ "$CAN_FOUND" == "true" ]]; then
    log "Setting CAN queue immediately to $CAN_QUEUE_LENGTH" "Setze CAN-Queue sofort auf $CAN_QUEUE_LENGTH"

    ip link set "$CAN_INTERFACE" txqueuelen "$CAN_QUEUE_LENGTH"

    systemctl restart set-can0-queue.service

    log "Current CAN configuration" "Aktuelle CAN-Konfiguration"

    ip -details link show "$CAN_INTERFACE"
else
    echo
    if [ "$IS_GERMAN" = true ]; then
        echo "Hinweis: $CAN_INTERFACE wurde aktuell nicht gefunden."
        echo "Der Queue-Service wartet beim nächsten Start auf das Interface."
    else
        echo "Notice: $CAN_INTERFACE not currently found."
        echo "The queue service will wait for the interface at next boot."
    fi
fi

log "Starting clean shutdown service" "Starte Clean-Shutdown-Service"

systemctl start "$SHUTDOWN_SERVICE"

echo
echo "============================================================"
if [ "$IS_GERMAN" = true ]; then
    echo "Installation abgeschlossen."
else
    echo "Installation completed."
fi
echo "============================================================"
echo
if [ "$IS_GERMAN" = true ]; then
    echo "Konfigurationsdatei:"
    echo "  $NETWORK_FILE"
    echo
    echo "Queue-Service:"
    echo "  $QUEUE_SERVICE"
    echo
    echo "Shutdown-Service:"
    echo "  $SHUTDOWN_SERVICE"
    echo
    echo "Backups:"
    echo "  $BACKUP_DIR"
else
    echo "Configuration file:"
    echo "  $NETWORK_FILE"
    echo
    echo "Queue service:"
    echo "  $QUEUE_SERVICE"
    echo
    echo "Shutdown service:"
    echo "  $SHUTDOWN_SERVICE"
    echo
    echo "Backups:"
    echo "  $BACKUP_DIR"
fi
echo

if ip link show "$CAN_INTERFACE" >/dev/null 2>&1; then
    CURRENT_QUEUE="$(ip -details link show "$CAN_INTERFACE" \
        | sed -n 's/.*qlen \([0-9]*\).*/\1/p')"

    if [ "$IS_GERMAN" = true ]; then
        echo "Aktuelle txqueuelen: ${CURRENT_QUEUE:-unbekannt}"
        echo "Erwartete txqueuelen: $CAN_QUEUE_LENGTH"
    else
        echo "Current txqueuelen: ${CURRENT_QUEUE:-unknown}"
        echo "Expected txqueuelen: $CAN_QUEUE_LENGTH"
    fi
else
    if [ "$IS_GERMAN" = true ]; then
        echo "can0 ist derzeit nicht vorhanden."
    else
        echo "can0 is currently not available."
    fi
fi

echo
if [ "$IS_GERMAN" = true ]; then
    echo "Nach einem Neustart prüfen mit:"
    echo "  ip -details link show can0"
    echo
    echo "Die Ausgabe sollte enthalten:"
    echo "  qlen $CAN_QUEUE_LENGTH"
else
    echo "Check after a reboot using:"
    echo "  ip -details link show can0"
    echo
    echo "The output should contain:"
    echo "  qlen $CAN_QUEUE_LENGTH"
fi
