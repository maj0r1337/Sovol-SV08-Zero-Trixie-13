#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Sovol SV08 / CB1
# CAN-Konfiguration für Debian/Armbian 13
#
# Enthalten:
# - systemd-networkd-Konfiguration für can0
# - CAN-Bitrate 1.000.000
# - TxQueueLength 128
# - Fallback-Service für txqueuelen
# - sauberes Entladen von gs_usb vor Reboot/Shutdown
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

log() {
    echo
    echo "==> $*"
}

error() {
    echo
    echo "FEHLER: $*" >&2
    exit 1
}

backup_file() {
    local file="$1"

    if [[ -e "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$file" "$BACKUP_DIR/"
        echo "Backup erstellt: $BACKUP_DIR/$(basename "$file")"
    fi
}

if [[ "${EUID}" -ne 0 ]]; then
    error "Dieses Skript muss mit sudo ausgeführt werden:
sudo $0"
fi

log "Prüfe benötigte Programme"

for command in ip systemctl modprobe; do
    if ! command -v "$command" >/dev/null 2>&1; then
        error "Benötigtes Programm nicht gefunden: $command"
    fi
done

log "Erstelle Backup-Verzeichnis"

mkdir -p "$BACKUP_DIR"

log "Sichere vorhandene Konfigurationsdateien"

backup_file "$NETWORK_FILE"
backup_file "$QUEUE_SCRIPT"
backup_file "$QUEUE_SERVICE"
backup_file "$SHUTDOWN_SCRIPT"
backup_file "$SHUTDOWN_SERVICE"

log "Erstelle systemd-networkd-Konfiguration"

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

log "Erstelle CAN-Queue-Fallback-Skript"

cat > "$QUEUE_SCRIPT" <<'EOF'
#!/usr/bin/env bash

set -u

CAN_INTERFACE="can0"
QUEUE_LENGTH="128"
IP_BIN="$(command -v ip)"

# Warten, bis das USB-CAN-Interface vorhanden ist
for attempt in {1..30}; do
    if "$IP_BIN" link show "$CAN_INTERFACE" >/dev/null 2>&1; then
        "$IP_BIN" link set "$CAN_INTERFACE" txqueuelen "$QUEUE_LENGTH"

        CURRENT_QUEUE="$("$IP_BIN" -details link show "$CAN_INTERFACE" \
            | sed -n 's/.*qlen \([0-9]*\).*/\1/p')"

        if [[ "$CURRENT_QUEUE" == "$QUEUE_LENGTH" ]]; then
            echo "$CAN_INTERFACE: txqueuelen=$CURRENT_QUEUE"
            exit 0
        fi

        echo "Fehler: txqueuelen konnte nicht gesetzt werden." >&2
        exit 1
    fi

    sleep 1
done

echo "$CAN_INTERFACE wurde innerhalb von 30 Sekunden nicht gefunden." >&2
exit 1
EOF

chmod 755 "$QUEUE_SCRIPT"

log "Erstelle systemd-Service für CAN-Queue"

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

log "Erstelle Clean-Shutdown-Skript"

cat > "$SHUTDOWN_SCRIPT" <<'EOF'
#!/bin/sh

if /usr/sbin/ip link show can0 >/dev/null 2>&1; then
    /usr/sbin/ip link set can0 down || true
    /sbin/modprobe -r gs_usb || true
fi

exit 0
EOF

chmod 755 "$SHUTDOWN_SCRIPT"

log "Erstelle Clean-Shutdown-Service"

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

log "Aktiviere systemd-networkd"

systemctl enable systemd-networkd.service

log "Lade systemd-Konfiguration neu"

systemctl daemon-reload

log "Aktiviere CAN-Services"

systemctl enable "$QUEUE_SERVICE"
systemctl enable "$SHUTDOWN_SERVICE"

log "Starte systemd-networkd neu"

systemctl restart systemd-networkd.service

log "Warte auf CAN-Interface"

CAN_FOUND="false"

for attempt in {1..30}; do
    if ip link show "$CAN_INTERFACE" >/dev/null 2>&1; then
        CAN_FOUND="true"
        break
    fi

    sleep 1
done

if [[ "$CAN_FOUND" == "true" ]]; then
    log "Setze CAN-Queue sofort auf $CAN_QUEUE_LENGTH"

    ip link set "$CAN_INTERFACE" txqueuelen "$CAN_QUEUE_LENGTH"

    systemctl restart set-can0-queue.service

    log "Aktuelle CAN-Konfiguration"

    ip -details link show "$CAN_INTERFACE"
else
    echo
    echo "Hinweis: $CAN_INTERFACE wurde aktuell nicht gefunden."
    echo "Der Queue-Service wartet beim nächsten Start auf das Interface."
fi

log "Starte Clean-Shutdown-Service"

systemctl start "$SHUTDOWN_SERVICE"

echo
echo "============================================================"
echo "Installation abgeschlossen."
echo "============================================================"
echo
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
echo

if ip link show "$CAN_INTERFACE" >/dev/null 2>&1; then
    CURRENT_QUEUE="$(ip -details link show "$CAN_INTERFACE" \
        | sed -n 's/.*qlen \([0-9]*\).*/\1/p')"

    echo "Aktuelle txqueuelen: ${CURRENT_QUEUE:-unbekannt}"
    echo "Erwartete txqueuelen: $CAN_QUEUE_LENGTH"
else
    echo "can0 ist derzeit nicht vorhanden."
fi

echo
echo "Nach einem Neustart prüfen mit:"
echo "  ip -details link show can0"
echo
echo "Die Ausgabe sollte enthalten:"
echo "  qlen $CAN_QUEUE_LENGTH"
