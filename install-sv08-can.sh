#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Sovol SV08 / CB1
# CAN configuration with delayed FIRMWARE_RESTART
#
# English is used by default.
# German is used automatically when the system locale is German.
# ============================================================

CAN_INTERFACE="can0"
CAN_BITRATE="1000000"
CAN_QUEUE_LENGTH="128"

KLIPPER_SERVICE="klipper.service"
MOONRAKER_SERVICE="moonraker.service"

MOONRAKER_URL="http://127.0.0.1:7125"
NETWORK_FILE="/etc/systemd/network/80-can0.network"

BACKUP_DIR="/root/sv08-can-backups/$(date +%Y%m%d-%H%M%S)"

# ============================================================
# Language detection
# ============================================================

SYSTEM_LOCALE="${LC_ALL:-${LC_MESSAGES:-${LANG:-en_US}}}"

if [[ "$SYSTEM_LOCALE" =~ ^de([_.@-]|$) ]]; then
    LANGUAGE="de"
else
    LANGUAGE="en"
fi

# ============================================================
# Localized output
# ============================================================

msg() {
    local key="$1"
    shift || true

    if [[ "$LANGUAGE" == "de" ]]; then
        case "$key" in
            root_error)
                printf '%s\n\nsudo %s\n' \
                    "Bitte als root ausführen:" "$0"
                ;;

            missing_command)
                printf "Der Befehl '%s' wurde nicht gefunden.\n" "$1"
                ;;

            curl_missing)
                printf '%s\n' \
                    "Der Befehl 'curl' wurde nicht gefunden. Bitte curl installieren."
                ;;

            service_missing)
                printf "Der Service '%s' wurde nicht gefunden.\n" "$1"
                ;;

            configuration)
                printf '%s\n' "CAN-Konfiguration:"
                ;;

            interface)
                printf "  Interface:  %s\n" "$1"
                ;;

            bitrate)
                printf "  Bitrate:    %s\n" "$1"
                ;;

            tx_queue)
                printf "  TX-Queue:   %s\n" "$1"
                ;;

            moonraker_url)
                printf "  Moonraker:  %s\n" "$1"
                ;;

            restart_info)
                printf '%s\n' \
                    "Nach der CAN-Konfiguration wird Klipper zunächst neu gestartet." \
                    "Danach wartet das Skript auf Moonraker und Klipper." \
                    "Erst anschließend wird FIRMWARE_RESTART ausgelöst."
                ;;

            continue_prompt)
                printf '%s' "Installation fortsetzen? [j/N] "
                ;;

            cancelled)
                printf '%s\n' "Installation abgebrochen."
                ;;

            backup_created)
                printf "Backup erstellt: %s\n" "$1"
                ;;

            load_can_module)
                printf '%s\n' "Lade CAN-USB-Kernelmodul"
                ;;

            module_error)
                printf '%s\n' "Das Kernelmodul gs_usb konnte nicht geladen werden."
                ;;

            create_network_config)
                printf '%s\n' "Erstelle systemd-networkd-Konfiguration"
                ;;

            restart_networkd)
                printf '%s\n' "Starte systemd-networkd neu"
                ;;

            wait_interface)
                printf "Warte auf %s\n" "$1"
                ;;

            interface_not_found)
                printf '%s\n\n' "$1 wurde nicht gefunden."
                printf '%s\n' \
                    "Prüfe:" \
                    "  ip link" \
                    "  lsmod | grep gs_usb" \
                    "  dmesg | grep -Ei 'can|usb|gs_usb'"
                ;;

            configure_interface)
                printf "Konfiguriere %s\n" "$1"
                ;;

            bitrate_error)
                printf "Bitrate für %s konnte nicht gesetzt werden.\n" "$1"
                ;;

            queue_error)
                printf "TX-Queue für %s konnte nicht gesetzt werden.\n" "$1"
                ;;

            interface_up_error)
                printf "%s konnte nicht aktiviert werden.\n" "$1"
                ;;

            restart_klipper)
                printf '%s\n' "Starte Klipper-Service neu"
                ;;

            klipper_restart_error)
                printf '%s\n' "Der Klipper-Service konnte nicht neu gestartet werden."
                ;;

            klipper_restarted)
                printf '%s\n' \
                    "Klipper wurde neu gestartet." \
                    "Warte auf den erfolgreichen Start von Klipper und Moonraker."
                ;;

            klipper_active)
                printf '%s\n' "Klipper-Service ist aktiv."
                ;;

            klipper_timeout)
                printf '%s\n' \
                    "Klipper ist nach 60 Sekunden nicht aktiv." \
                    "Klipper konnte nicht gestartet werden."
                ;;

            wait_moonraker)
                printf '%s\n' "Warte auf Moonraker"
                ;;

            moonraker_available)
                printf '%s\n' "Moonraker ist erreichbar."
                ;;

            moonraker_timeout)
                printf '%s\n' \
                    "Moonraker ist nach 60 Sekunden nicht erreichbar." \
                    "" \
                    "Prüfe:" \
                    "  systemctl status $MOONRAKER_SERVICE" \
                    "  journalctl -u $MOONRAKER_SERVICE -n 50 --no-pager"
                ;;

            wait_mcus)
                printf '%s\n' \
                    "Warte auf die CAN-MCUs" \
                    "Zusätzliche Wartezeit: 20 Sekunden"
                ;;

            prepare_firmware_restart)
                printf '%s\n' "Bereite FIRMWARE_RESTART vor"
                ;;

            firmware_countdown)
                printf '\rFirmware-Neustart in %2d Sekunden... ' "$1"
                ;;

            firmware_attempt)
                printf 'FIRMWARE_RESTART-Versuch %s von 5 ...\n' "$1"
                ;;

            firmware_success)
                printf '%s\n' "FIRMWARE_RESTART wurde erfolgreich gesendet."
                ;;

            firmware_retry)
                printf '%s\n' \
                    "Moonraker/Klipper ist noch nicht bereit." \
                    "Warte 10 Sekunden vor dem nächsten Versuch."
                ;;

            firmware_warning)
                printf '%s\n' \
                    "WARNUNG: FIRMWARE_RESTART konnte nicht bestätigt werden." \
                    "Bitte in Mainsail manuell FIRMWARE_RESTART ausführen."
                ;;

            completed)
                printf '%s\n' "Vorgang abgeschlossen"
                ;;

            klipper_status)
                printf '%s\n' "Klipper-Status:"
                ;;

            latest_messages)
                printf '%s\n' "Letzte Klipper-Meldungen:"
                ;;

            diagnostic_commands)
                printf '%s\n' "Diagnosebefehle:"
                ;;
        esac
    else
        case "$key" in
            root_error)
                printf '%s\n\nsudo %s\n' \
                    "Please run this script as root:" "$0"
                ;;

            missing_command)
                printf "Command '%s' was not found.\n" "$1"
                ;;

            curl_missing)
                printf '%s\n' \
                    "The command 'curl' was not found. Please install curl."
                ;;

            service_missing)
                printf "The service '%s' was not found.\n" "$1"
                ;;

            configuration)
                printf '%s\n' "CAN configuration:"
                ;;

            interface)
                printf "  Interface:  %s\n" "$1"
                ;;

            bitrate)
                printf "  Bitrate:    %s\n" "$1"
                ;;

            tx_queue)
                printf "  TX queue:   %s\n" "$1"
                ;;

            moonraker_url)
                printf "  Moonraker:  %s\n" "$1"
                ;;

            restart_info)
                printf '%s\n' \
                    "After the CAN configuration, Klipper will be restarted first." \
                    "The script will then wait for Moonraker and Klipper." \
                    "Only afterwards will FIRMWARE_RESTART be triggered."
                ;;

            continue_prompt)
                printf '%s' "Continue installation? [y/N] "
                ;;

            cancelled)
                printf '%s\n' "Installation cancelled."
                ;;

            backup_created)
                printf "Backup created: %s\n" "$1"
                ;;

            load_can_module)
                printf '%s\n' "Loading CAN USB kernel module"
                ;;

            module_error)
                printf '%s\n' "The gs_usb kernel module could not be loaded."
                ;;

            create_network_config)
                printf '%s\n' "Creating systemd-networkd configuration"
                ;;

            restart_networkd)
                printf '%s\n' "Restarting systemd-networkd"
                ;;

            wait_interface)
                printf "Waiting for %s\n" "$1"
                ;;

            interface_not_found)
                printf '%s\n\n' "$1 was not found."
                printf '%s\n' \
                    "Check:" \
                    "  ip link" \
                    "  lsmod | grep gs_usb" \
                    "  dmesg | grep -Ei 'can|usb|gs_usb'"
                ;;

            configure_interface)
                printf "Configuring %s\n" "$1"
                ;;

            bitrate_error)
                printf "Could not set the bitrate for %s.\n" "$1"
                ;;

            queue_error)
                printf "Could not set the TX queue for %s.\n" "$1"
                ;;

            interface_up_error)
                printf "%s could not be activated.\n" "$1"
                ;;

            restart_klipper)
                printf '%s\n' "Restarting Klipper service"
                ;;

            klipper_restart_error)
                printf '%s\n' "The Klipper service could not be restarted."
                ;;

            klipper_restarted)
                printf '%s\n' \
                    "Klipper was restarted." \
                    "Waiting for Klipper and Moonraker to start successfully."
                ;;

            klipper_active)
                printf '%s\n' "Klipper service is active."
                ;;

            klipper_timeout)
                printf '%s\n' \
                    "Klipper was not active after 60 seconds." \
                    "Klipper could not be started."
                ;;

            wait_moonraker)
                printf '%s\n' "Waiting for Moonraker"
                ;;

            moonraker_available)
                printf '%s\n' "Moonraker is reachable."
                ;;

            moonraker_timeout)
                printf '%s\n' \
                    "Moonraker was not reachable after 60 seconds." \
                    "" \
                    "Check:" \
                    "  systemctl status $MOONRAKER_SERVICE" \
                    "  journalctl -u $MOONRAKER_SERVICE -n 50 --no-pager"
                ;;

            wait_mcus)
                printf '%s\n' \
                    "Waiting for CAN MCUs" \
                    "Additional waiting time: 20 seconds"
                ;;

            prepare_firmware_restart)
                printf '%s\n' "Preparing FIRMWARE_RESTART"
                ;;

            firmware_countdown)
                printf '\rFirmware restart in %2d seconds... ' "$1"
                ;;

            firmware_attempt)
                printf 'FIRMWARE_RESTART attempt %s of 5 ...\n' "$1"
                ;;

            firmware_success)
                printf '%s\n' "FIRMWARE_RESTART was sent successfully."
                ;;

            firmware_retry)
                printf '%s\n' \
                    "Moonraker/Klipper is not ready yet." \
                    "Waiting 10 seconds before the next attempt."
                ;;

            firmware_warning)
                printf '%s\n' \
                    "WARNING: FIRMWARE_RESTART could not be confirmed." \
                    "Please run FIRMWARE_RESTART manually in Mainsail."
                ;;

            completed)
                printf '%s\n' "Operation completed"
                ;;

            klipper_status)
                printf '%s\n' "Klipper status:"
                ;;

            latest_messages)
                printf '%s\n' "Latest Klipper messages:"
                ;;

            diagnostic_commands)
                printf '%s\n' "Diagnostic commands:"
                ;;
        esac
    fi
}

# ============================================================
# Helper functions
# ============================================================

log() {
    echo
    echo "==> $1"
}

error_exit() {
    echo

    if [[ "$LANGUAGE" == "de" ]]; then
        printf 'FEHLER: %s\n' "$1" >&2
    else
        printf 'ERROR: %s\n' "$1" >&2
    fi

    exit 1
}

backup_file() {
    local file="$1"

    if [[ -e "$file" || -L "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$file" "$BACKUP_DIR/"
        msg backup_created "$BACKUP_DIR/$(basename "$file")"
    fi
}

can_exists() {
    "$IP_BIN" link show "$CAN_INTERFACE" >/dev/null 2>&1
}

show_can_status() {
    echo

    if [[ "$LANGUAGE" == "de" ]]; then
        echo "CAN-Status:"
    else
        echo "CAN status:"
    fi

    "$IP_BIN" -details link show "$CAN_INTERFACE" 2>/dev/null || true
}

moonraker_available() {
    "$CURL_BIN" \
        --silent \
        --show-error \
        --fail \
        --max-time 5 \
        "$MOONRAKER_URL/printer/info" \
        >/dev/null 2>&1
}

# ============================================================
# Check prerequisites
# ============================================================

if [[ "${EUID}" -ne 0 ]]; then
    error_exit "$(msg root_error)"
fi

IP_BIN="$(command -v ip || true)"
MODPROBE_BIN="$(command -v modprobe || true)"
SYSTEMCTL_BIN="$(command -v systemctl || true)"
CURL_BIN="$(command -v curl || true)"

[[ -n "$IP_BIN" ]] || error_exit "$(msg missing_command ip)"
[[ -n "$MODPROBE_BIN" ]] || error_exit "$(msg missing_command modprobe)"
[[ -n "$SYSTEMCTL_BIN" ]] || error_exit "$(msg missing_command systemctl)"
[[ -n "$CURL_BIN" ]] || error_exit "$(msg curl_missing)"

if ! "$SYSTEMCTL_BIN" list-unit-files "$KLIPPER_SERVICE" \
    >/dev/null 2>&1; then

    error_exit "$(msg service_missing "$KLIPPER_SERVICE")"
fi

# ============================================================
# Confirmation
# ============================================================

echo
msg configuration
echo
msg interface "$CAN_INTERFACE"
msg bitrate "$CAN_BITRATE"
msg tx_queue "$CAN_QUEUE_LENGTH"
msg moonraker_url "$MOONRAKER_URL"
echo
msg restart_info
echo

read -r -p "$(msg continue_prompt)" ANSWER

if [[ "$LANGUAGE" == "de" ]]; then
    ACCEPTED_ANSWER='^[JjYy]$'
else
    ACCEPTED_ANSWER='^[YyJj]$'
fi

if [[ ! "$ANSWER" =~ $ACCEPTED_ANSWER ]]; then
    msg cancelled
    exit 0
fi

# ============================================================
# Create backup
# ============================================================

log "Creating backup"
mkdir -p "$BACKUP_DIR"
backup_file "$NETWORK_FILE"

# ============================================================
# Load CAN kernel module
# ============================================================

log "$(msg load_can_module)"

if ! "$MODPROBE_BIN" gs_usb; then
    error_exit "$(msg module_error)"
fi

# ============================================================
# Create systemd-networkd configuration
# ============================================================

log "$(msg create_network_config)"

mkdir -p /etc/systemd/network

cat > "$NETWORK_FILE" <<EOF
[Match]
Name=$CAN_INTERFACE

[Link]
RequiredForOnline=no
TxQueueLength=$CAN_QUEUE_LENGTH

[Network]
ConfigureWithoutCarrier=yes

[CAN]
BitRate=$CAN_BITRATE
EOF

chmod 0644 "$NETWORK_FILE"

"$SYSTEMCTL_BIN" daemon-reload
"$SYSTEMCTL_BIN" enable systemd-networkd.service >/dev/null 2>&1 || true

# ============================================================
# Restart systemd-networkd
# ============================================================

log "$(msg restart_networkd)"

"$SYSTEMCTL_BIN" restart systemd-networkd.service

# ============================================================
# Wait for CAN interface
# ============================================================

log "$(msg wait_interface "$CAN_INTERFACE")"

CAN_FOUND=false

for attempt in {1..30}; do
    if can_exists; then
        CAN_FOUND=true
        break
    fi

    sleep 1
done

if [[ "$CAN_FOUND" != true ]]; then
    error_exit "$(msg interface_not_found "$CAN_INTERFACE")"
fi

# ============================================================
# Configure CAN interface
# ============================================================

log "$(msg configure_interface "$CAN_INTERFACE")"

"$IP_BIN" link set "$CAN_INTERFACE" down 2>/dev/null || true

if ! "$IP_BIN" link set "$CAN_INTERFACE" \
    type can \
    bitrate "$CAN_BITRATE"; then

    error_exit "$(msg bitrate_error "$CAN_INTERFACE")"
fi

if ! "$IP_BIN" link set "$CAN_INTERFACE" \
    txqueuelen "$CAN_QUEUE_LENGTH"; then

    error_exit "$(msg queue_error "$CAN_INTERFACE")"
fi

if ! "$IP_BIN" link set "$CAN_INTERFACE" up; then
    error_exit "$(msg interface_up_error "$CAN_INTERFACE")"
fi

sleep 2
show_can_status

# ============================================================
# Restart Klipper
# ============================================================

log "$(msg restart_klipper)"

if ! "$SYSTEMCTL_BIN" restart "$KLIPPER_SERVICE"; then
    error_exit "$(msg klipper_restart_error)"
fi

echo
msg klipper_restarted

# ============================================================
# Wait for active Klipper service
# ============================================================

KLIPPER_ACTIVE=false

for attempt in {1..60}; do
    if "$SYSTEMCTL_BIN" is-active --quiet "$KLIPPER_SERVICE"; then
        KLIPPER_ACTIVE=true
        msg klipper_active
        break
    fi

    sleep 1
done

if [[ "$KLIPPER_ACTIVE" != true ]]; then
    echo
    msg klipper_timeout
    echo

    "$SYSTEMCTL_BIN" --no-pager --full status \
        "$KLIPPER_SERVICE" || true

    echo

    if [[ "$LANGUAGE" == "de" ]]; then
        echo "Journal:"
    else
        echo "Journal:"
    fi

    "$SYSTEMCTL_BIN" --no-pager journal \
        "$KLIPPER_SERVICE" \
        -n 50 \
        -o cat || true

    error_exit "$(msg klipper_timeout)"
fi

# ============================================================
# Wait for Moonraker
# ============================================================

log "$(msg wait_moonraker)"

MOONRAKER_READY=false

for attempt in {1..60}; do
    if moonraker_available; then
        MOONRAKER_READY=true
        msg moonraker_available
        break
    fi

    sleep 1
done

if [[ "$MOONRAKER_READY" != true ]]; then
    error_exit "$(msg moonraker_timeout)"
fi

# ============================================================
# Additional wait time for MCU connections
# ============================================================

log "$(msg wait_mcus)"
sleep 20

show_can_status

# ============================================================
# Firmware restart with retries
# ============================================================

log "$(msg prepare_firmware_restart)"

echo

if [[ "$LANGUAGE" == "de" ]]; then
    echo "FIRMWARE_RESTART wird in 5 Sekunden ausgelöst."
else
    echo "FIRMWARE_RESTART will be triggered in 5 seconds."
fi

for seconds in 5 4 3 2 1; do
    msg firmware_countdown "$seconds"
    sleep 1
done

echo
echo

FIRMWARE_RESTART_OK=false

for attempt in 1 2 3 4 5; do
    msg firmware_attempt "$attempt"

    if "$CURL_BIN" \
        --silent \
        --show-error \
        --fail \
        --max-time 15 \
        -X POST \
        "$MOONRAKER_URL/printer/firmware_restart"; then

        FIRMWARE_RESTART_OK=true
        msg firmware_success
        break
    fi

    msg firmware_retry
    sleep 10
done

if [[ "$FIRMWARE_RESTART_OK" != true ]]; then
    echo
    msg firmware_warning
fi

# ============================================================
# Finish
# ============================================================

sleep 10

echo
echo "============================================================"
msg completed
echo "============================================================"

echo
msg klipper_status
"$SYSTEMCTL_BIN" --no-pager --full status \
    "$KLIPPER_SERVICE" || true

echo
show_can_status

echo
msg latest_messages
"$SYSTEMCTL_BIN" --no-pager journal \
    "$KLIPPER_SERVICE" \
    -n 50 \
    -o cat 2>/dev/null || true

echo
msg diagnostic_commands
echo
echo "  ip -details link show $CAN_INTERFACE"
echo "  systemctl status $KLIPPER_SERVICE"
echo "  journalctl -u $KLIPPER_SERVICE -n 100 --no-pager"
echo "  dmesg | grep -Ei 'can|usb|gs_usb'"
echo
