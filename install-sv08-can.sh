#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# CAN-Schnittstelle dauerhaft konfigurieren
#
# Basiert auf dem manuellen Tutorial:
#   1. systemd-networkd CAN-Konfiguration
#   2. Clean-Shutdown-Service
#   3. qlen dauerhaft auf 128 setzen
#   4. qlen systemd-Service
#   5. Prüfung
# ============================================================

NETWORK_FILE="/etc/systemd/network/80-can0.network"
DISCONNECT_SCRIPT="/usr/local/bin/disconnect-can.sh"
SHUTDOWN_SERVICE="/etc/systemd/system/can-shutdown.service"
QUEUE_SCRIPT="/usr/local/sbin/set-can0-queue.sh"
QUEUE_SERVICE="/etc/systemd/system/set-can0-queue.service"

echo
echo "============================================================"
echo " CAN0 Installation"
echo "============================================================"
echo

# ------------------------------------------------------------
# Root-Rechte prüfen
# ------------------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Dieses Skript muss als root ausgeführt werden."
    echo "Bitte verwenden:"
    echo "  sudo ./install-can.sh"
    exit 1
fi

# ------------------------------------------------------------
# Benötigte Programme prüfen
# ------------------------------------------------------------

echo "==> Prüfe benötigte Programme"

for cmd in ip systemctl modprobe; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Benötigtes Programm nicht gefunden: $cmd"
        exit 1
    fi
done

echo "    OK"
echo

# ------------------------------------------------------------
# 1. systemd-networkd CAN-Konfiguration
# ------------------------------------------------------------

echo "==> 1/5 Erstelle $NETWORK_FILE"

mkdir -p /etc/systemd/network

cat > "$NETWORK_FILE" <<'EOF'
[Match]
Name=can0

[Link]
TxQueueLength=128

[Network]
CAN=true

[CAN]
BitRate=1000000
EOF

echo "    OK"
echo

# ------------------------------------------------------------
# systemd-networkd aktivieren und neu starten
# ------------------------------------------------------------

echo "==> Aktiviere systemd-networkd"

systemctl enable systemd-networkd

echo "==> Starte systemd-networkd neu"

systemctl restart systemd-networkd

echo "    OK"
echo

# ------------------------------------------------------------
# 2. Clean-Shutdown-Skript
# ------------------------------------------------------------

echo "==> 2/5 Erstelle $DISCONNECT_SCRIPT"

mkdir -p /usr/local/bin

cat > "$DISCONNECT_SCRIPT" <<'EOF'
#!/bin/sh

if ip link show can0 >/dev/null 2>&1; then
    /usr/sbin/ip link set can0 down
    /usr/sbin/modprobe -r gs_usb
fi
EOF

chmod +x "$DISCONNECT_SCRIPT"

echo "    Skript erstellt und ausführbar gemacht."
echo

# ------------------------------------------------------------
# Clean-Shutdown-Service
# ------------------------------------------------------------

echo "==> Erstelle $SHUTDOWN_SERVICE"

cat > "$SHUTDOWN_SERVICE" <<'EOF'
[Unit]
Description=Clean CAN-Bus disconnect before reboot
After=klipper.service systemd-networkd.service
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=/usr/local/bin/disconnect-can.sh

[Install]
WantedBy=multi-user.target
EOF

echo "    OK"
echo

# ------------------------------------------------------------
# Clean-Shutdown-Service aktivieren
# ------------------------------------------------------------

echo "==> Lade systemd-Konfiguration neu"

systemctl daemon-reload

echo "==> Aktiviere can-shutdown.service"

systemctl enable can-shutdown.service

echo "==> Starte can-shutdown.service"

systemctl start can-shutdown.service

echo "    OK"
echo

# ------------------------------------------------------------
# 3. qlen-Skript
# ------------------------------------------------------------

echo "==> 3/5 Erstelle $QUEUE_SCRIPT"

mkdir -p /usr/local/sbin

cat > "$QUEUE_SCRIPT" <<'EOF'
#!/bin/bash

# Warten, bis can0 vom USB-CAN-Adapter angelegt wurde
for i in {1..30}; do
    if ip link show can0 >/dev/null 2>&1; then
        /sbin/ip link set can0 txqueuelen 128
        exit 0
    fi
    sleep 1
done

echo "can0 wurde nicht gefunden" >&2
exit 1
EOF

chmod +x "$QUEUE_SCRIPT"

echo "    Skript erstellt und ausführbar gemacht."
echo

# ------------------------------------------------------------
# 4. qlen systemd-Service
# ------------------------------------------------------------

echo "==> 4/5 Erstelle $QUEUE_SERVICE"

cat > "$QUEUE_SERVICE" <<'EOF'
[Unit]
Description=Set CAN0 transmit queue length
After=network-online.target
Wants=network-online.target
Before=klipper.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/set-can0-queue.sh
RemainAfterExit=yes
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

echo "    OK"
echo

# ------------------------------------------------------------
# qlen-Service aktivieren
# ------------------------------------------------------------

echo "==> Lade systemd-Konfiguration neu"

systemctl daemon-reload

echo "==> Aktiviere set-can0-queue.service"

systemctl enable set-can0-queue.service

echo "==> Starte set-can0-queue.service"

systemctl start set-can0-queue.service

echo "    OK"
echo

# ------------------------------------------------------------
# 5. Prüfung
# ------------------------------------------------------------

echo "============================================================"
echo " 5/5 Prüfung"
echo "============================================================"
echo

echo "==> Status von set-can0-queue.service:"
echo

systemctl status set-can0-queue.service --no-pager || true

echo
echo "==> CAN0 Interface:"
echo

ip -details link show can0

echo
echo "============================================================"
echo " Installation abgeschlossen."
echo "============================================================"
echo
```
