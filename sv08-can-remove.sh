#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# CAN0-Konfiguration rückgängig machen
#
# Entfernt alle Dateien und systemd-Einstellungen, die durch
# install-can.sh erstellt wurden.
#
# Entfernt NICHT:
#   - systemd-networkd selbst
#   - das CAN-Kernelmodul
#   - andere CAN-Konfigurationen
# ============================================================

NETWORK_FILE="/etc/systemd/network/80-can0.network"
DISCONNECT_SCRIPT="/usr/local/bin/disconnect-can.sh"
SHUTDOWN_SERVICE="/etc/systemd/system/can-shutdown.service"
QUEUE_SCRIPT="/usr/local/sbin/set-can0-queue.sh"
QUEUE_SERVICE="/etc/systemd/system/set-can0-queue.service"

echo
echo "============================================================"
echo " CAN0 Deinstallation"
echo "============================================================"
echo

# ------------------------------------------------------------
# Root-Rechte prüfen
# ------------------------------------------------------------

if [[ "${EUID}" -ne 0 ]]; then
    echo "ERROR: Dieses Skript muss als root ausgeführt werden."
    echo "Bitte verwenden:"
    echo "  sudo ./uninstall-can.sh"
    exit 1
fi

# ------------------------------------------------------------
# Prüfen, ob überhaupt etwas vorhanden ist
# ------------------------------------------------------------

echo "==> Prüfe vorhandene CAN0-Konfiguration"

FOUND=false

for file in \
    "$NETWORK_FILE" \
    "$DISCONNECT_SCRIPT" \
    "$SHUTDOWN_SERVICE" \
    "$QUEUE_SCRIPT" \
    "$QUEUE_SERVICE"
do
    if [[ -e "$file" ]]; then
        FOUND=true
        echo "    Gefunden: $file"
    fi
done

if [[ "$FOUND" == false ]]; then
    echo
    echo "============================================================"
    echo " Die CAN0-Konfiguration ist bereits entfernt."
    echo " Es gibt nichts zu tun."
    echo "============================================================"
    echo
    exit 0
fi

echo

# ------------------------------------------------------------
# Sicherheitsabfrage
# ------------------------------------------------------------

echo "============================================================"
echo " ACHTUNG!"
echo
echo " Die folgenden CAN0-Dateien und systemd-Einstellungen"
echo " werden entfernt:"
echo
echo "   $NETWORK_FILE"
echo "   $DISCONNECT_SCRIPT"
echo "   $SHUTDOWN_SERVICE"
echo "   $QUEUE_SCRIPT"
echo "   $QUEUE_SERVICE"
echo
echo " Die CAN0-Konfiguration wird damit rückgängig gemacht."
echo "============================================================"
echo

read -r -p "Möchtest du wirklich fortfahren? [j/N] " CONFIRM

case "$CONFIRM" in
    j|J)
        echo
        echo "Deinstallation wird durchgeführt."
        echo
        ;;
    *)
        echo
        echo "Deinstallation abgebrochen."
        echo "Es wurden keine Änderungen vorgenommen."
        echo
        exit 0
        ;;
esac

# ------------------------------------------------------------
# Clean-Shutdown-Service stoppen und deaktivieren
# ------------------------------------------------------------

echo "==> Bearbeite can-shutdown.service"

if systemctl is-active --quiet can-shutdown.service; then
    echo "    Stoppe can-shutdown.service"
    systemctl stop can-shutdown.service
else
    echo "    Service ist nicht aktiv."
fi

if systemctl is-enabled --quiet can-shutdown.service 2>/dev/null; then
    echo "    Deaktiviere can-shutdown.service"
    systemctl disable can-shutdown.service
else
    echo "    Service ist nicht aktiviert."
fi

echo

# ------------------------------------------------------------
# qlen-Service stoppen und deaktivieren
# ------------------------------------------------------------

echo "==> Bearbeite set-can0-queue.service"

if systemctl is-active --quiet set-can0-queue.service; then
    echo "    Stoppe set-can0-queue.service"
    systemctl stop set-can0-queue.service
else
    echo "    Service ist nicht aktiv."
fi

if systemctl is-enabled --quiet set-can0-queue.service 2>/dev/null; then
    echo "    Deaktiviere set-can0-queue.service"
    systemctl disable set-can0-queue.service
else
    echo "    Service ist nicht aktiviert."
fi

echo

# ------------------------------------------------------------
# systemd-Konfiguration neu laden
# ------------------------------------------------------------

echo "==> Lade systemd-Konfiguration neu"

systemctl daemon-reload

echo "    OK"
echo

# ------------------------------------------------------------
# Erstellte Dateien entfernen
# ------------------------------------------------------------

echo "==> Entferne erstellte Dateien"

for file in \
    "$NETWORK_FILE" \
    "$DISCONNECT_SCRIPT" \
    "$SHUTDOWN_SERVICE" \
    "$QUEUE_SCRIPT" \
    "$QUEUE_SERVICE"
do
    if [[ -e "$file" ]]; then
        rm -f "$file"
        echo "    Entfernt: $file"
    else
        echo "    Nicht vorhanden: $file"
    fi
done

echo

# ------------------------------------------------------------
# systemd-Konfiguration erneut laden
# ------------------------------------------------------------

echo "==> Lade systemd-Konfiguration erneut"

systemctl daemon-reload

echo "    OK"
echo

# ------------------------------------------------------------
# Abschluss
# ------------------------------------------------------------

echo "============================================================"
echo " CAN0-Deinstallation abgeschlossen."
echo "============================================================"
echo
echo " Die durch das Installationsskript erstellten Dateien"
echo " und systemd-Einstellungen wurden entfernt."
echo
echo " Hinweis:"
echo " Falls can0 aktuell noch aktiv ist, kann ein Neustart"
echo " erforderlich sein, damit die vorherige Netzwerkkonfiguration"
echo " vollständig wiederhergestellt wird."
echo
echo "============================================================"
echo
