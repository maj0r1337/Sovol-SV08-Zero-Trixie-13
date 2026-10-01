#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# Sovol SV08 / CB1
# Remove CAN configuration created by the installation script
#
# English is used by default.
# German is used automatically when the system locale is German.
# ============================================================

CAN_INTERFACE="can0"

NETWORK_FILE="/etc/systemd/network/80-can0.network"

QUEUE_SCRIPT="/usr/local/sbin/set-can0-queue.sh"
QUEUE_SERVICE="/etc/systemd/system/set-can0-queue.service"
QUEUE_UNIT="set-can0-queue.service"

SHUTDOWN_SCRIPT="/usr/local/bin/disconnect-can.sh"
SHUTDOWN_SERVICE="/etc/systemd/system/can-shutdown.service"
SHUTDOWN_UNIT="can-shutdown.service"

SYSTEMCTL_BIN="$(command -v systemctl || true)"
IP_BIN="$(command -v ip || true)"
MODPROBE_BIN="$(command -v modprobe || true)"
CURL_BIN="$(command -v curl || true)"

MOONRAKER_URL="http://127.0.0.1:7125"

SYSTEM_LOCALE="${LC_ALL:-${LC_MESSAGES:-${LANG:-en_US}}}"

if [[ "$SYSTEM_LOCALE" =~ ^de([_.@-]|$) ]]; then
    LANGUAGE="de"
else
    LANGUAGE="en"
fi

# ============================================================
# Localized messages
# ============================================================

msg() {
    local key="$1"
    shift || true

    if [[ "$LANGUAGE" == "de" ]]; then
        case "$key" in
            root_error)
                printf '%s\n\nsudo %s\n' \
                    "Dieses Skript muss als root ausgeführt werden." "$0"
                ;;

            missing_systemctl)
                printf '%s\n' "Fehler: systemctl wurde nicht gefunden."
                ;;

            configuration)
                printf '%s\n' \
                    "Dieses Skript entfernt die folgende CAN-Konfiguration:"
                ;;

            shutdown_info)
                printf '%s\n' \
                    "Außerdem wird versucht, $CAN_INTERFACE herunterzufahren" \
                    "und das Kernelmodul gs_usb zu entfernen."
                ;;

            continue_prompt)
                printf '%s' "Wirklich fortfahren? [j/N] "
                ;;

            cancelled)
                printf '%s\n' "Abgebrochen."
                ;;

            stopping_services)
                printf '%s\n' \
                    "Stoppe und deaktiviere systemd-Services..."
                ;;

            stopping_service)
                printf "Stoppe Service: %s\n" "$1"
                ;;

            interface_down)
                printf "Fahre %s herunter...\n" "$1"
                ;;

            remove_module)
                printf '%s\n' "Entferne Kernelmodul gs_usb..."
                ;;

            reload_systemd)
                printf '%s\n' \
                    "Lade systemd-Konfiguration neu..."
                ;;

            removing_files)
                printf '%s\n' \
                    "Entferne erstellte Dateien..."
                ;;

            removing_file)
                printf "Entferne: %s\n" "$1"
                ;;

            file_missing)
                printf "Nicht vorhanden: %s\n" "$1"
                ;;

            restart_networkd)
                printf '%s\n' \
                    "Starte systemd-networkd neu, damit die entfernte" \
                    "CAN-Konfiguration nicht erneut verwendet wird..."
                ;;

            networkd_restart_failed)
                printf '%s\n' \
                    "WARNUNG: systemd-networkd konnte nicht neu gestartet werden."
                ;;

            completed)
                printf '%s\n' \
                    "Die CAN-Konfiguration wurde entfernt."
                ;;

            backups)
                printf '%s\n' \
                    "Vorhandene Backups unter /root/sv08-can-backups/" \
                    "wurden nicht gelöscht."
                ;;

            check_result)
                printf '%s\n' \
                    "Prüfen kannst du das Ergebnis mit:"
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
                    "FIRMWARE_RESTART konnte noch nicht bestätigt werden." \
                    "Warte 10 Sekunden vor dem nächsten Versuch."
                ;;

            firmware_warning)
                printf '%s\n' \
                    "WARNUNG: FIRMWARE_RESTART konnte nicht bestätigt werden." \
                    "Der System-Reboot wird trotzdem durchgeführt."
                ;;

            reboot_notice)
                printf '%s\n' \
                    "Die Bereinigung ist abgeschlossen." \
                    "Der Drucker wird jetzt sauber neu gestartet."
                ;;
        esac
    else
        case "$key" in
            root_error)
                printf '%s\n\nsudo %s\n' \
                    "This script must be run as root." "$0"
                ;;

            missing_systemctl)
                printf '%s\n' "ERROR: systemctl was not found."
                ;;

            configuration)
                printf '%s\n' \
                    "This script will remove the following CAN configuration:"
                ;;

            shutdown_info)
                printf '%s\n' \
                    "It will also attempt to bring down $CAN_INTERFACE" \
                    "and remove the gs_usb kernel module."
                ;;

            continue_prompt)
                printf '%s' "Continue? [y/N] "
                ;;

            cancelled)
                printf '%s\n' "Cancelled."
                ;;

            stopping_services)
                printf '%s\n' \
                    "Stopping and disabling systemd services..."
                ;;

            stopping_service)
                printf "Stopping service: %s\n" "$1"
                ;;

            interface_down)
                printf "Bringing down %s...\n" "$1"
                ;;

            remove_module)
                printf '%s\n' "Removing gs_usb kernel module..."
                ;;

            reload_systemd)
                printf '%s\n' \
                    "Reloading systemd configuration..."
                ;;

            removing_files)
                printf '%s\n' \
                    "Removing created files..."
                ;;

            removing_file)
                printf "Removing: %s\n" "$1"
                ;;

            file_missing)
                printf "Not present: %s\n" "$1"
                ;;

            restart_networkd)
                printf '%s\n' \
                    "Restarting systemd-networkd so the removed" \
                    "CAN configuration is no longer used..."
                ;;

            networkd_restart_failed)
                printf '%s\n' \
                    "WARNING: systemd-networkd could not be restarted."
                ;;

            completed)
                printf '%s\n' \
                    "The CAN configuration has been removed."
                ;;

            backups)
                printf '%s\n' \
                    "Existing backups in /root/sv08-can-backups/" \
                    "were not deleted."
                ;;

            check_result)
                printf '%s\n' \
                    "You can check the result with:"
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
                    "FIRMWARE_RESTART could not be confirmed yet." \
                    "Waiting 10 seconds before the next attempt."
                ;;

            firmware_warning)
                printf '%s\n' \
                    "WARNING: FIRMWARE_RESTART could not be confirmed." \
                    "The system reboot will still be performed."
                ;;

            reboot_notice)
                printf '%s\n' \
                    "The cleanup is complete." \
                    "The printer will now reboot cleanly."
                ;;
        esac
    fi
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

remove_file() {
    local file="$1"

    if [[ -e "$file" || -L "$file" ]]; then
        msg removing_file "$file"
        rm -f -- "$file"
    else
        msg file_missing "$file"
    fi
}

stop_and_disable_service() {
    local unit="$1"

    if "$SYSTEMCTL_BIN" list-unit-files "$unit" \
        >/dev/null 2>&1; then

        msg stopping_service "$unit"

        "$SYSTEMCTL_BIN" disable --now "$unit" \
            >/dev/null 2>&1 || true

        "$SYSTEMCTL_BIN" stop "$unit" \
            >/dev/null 2>&1 || true
    fi
}

# ============================================================
# Root check
# ============================================================

if [[ "${EUID}" -ne 0 ]]; then
    error_exit "$(msg root_error)"
fi

if [[ -z "$SYSTEMCTL_BIN" ]]; then
    error_exit "$(msg missing_systemctl)"
fi

# ============================================================
# Confirmation
# ============================================================

echo
msg configuration
echo
echo "  $NETWORK_FILE"
echo "  $QUEUE_SCRIPT"
echo "  $QUEUE_SERVICE"
echo "  $SHUTDOWN_SCRIPT"
echo "  $SHUTDOWN_SERVICE"
echo
msg shutdown_info
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
# Stop and disable services
# ============================================================

echo
msg stopping_services

stop_and_disable_service "$QUEUE_UNIT"
stop_and_disable_service "$SHUTDOWN_UNIT"

# ============================================================
# Bring down CAN interface
# ============================================================

if [[ -n "$IP_BIN" ]] && \
   "$IP_BIN" link show "$CAN_INTERFACE" >/dev/null 2>&1; then

    msg interface_down "$CAN_INTERFACE"
    "$IP_BIN" link set "$CAN_INTERFACE" down 2>/dev/null || true
fi

# ============================================================
# Remove CAN kernel module
# ============================================================

if [[ -n "$MODPROBE_BIN" ]]; then
    msg remove_module
    "$MODPROBE_BIN" -r gs_usb 2>/dev/null || true
fi

# ============================================================
# Remove created files
# ============================================================

echo
msg removing_files

remove_file "$NETWORK_FILE"
remove_file "$QUEUE_SCRIPT"
remove_file "$QUEUE_SERVICE"
remove_file "$SHUTDOWN_SCRIPT"
remove_file "$SHUTDOWN_SERVICE"

# ============================================================
# Reload systemd
# ============================================================

echo
msg reload_systemd

"$SYSTEMCTL_BIN" daemon-reload
"$SYSTEMCTL_BIN" reset-failed 2>/dev/null || true

# ============================================================
# Restart systemd-networkd
# ============================================================
#
# This ensures that systemd-networkd forgets the removed
# 80-can0.network configuration.
#
# The restart is intentionally performed after removing the
# network configuration and after unloading gs_usb.
# ============================================================

echo
msg restart_networkd

if ! "$SYSTEMCTL_BIN" restart systemd-networkd.service; then
    msg networkd_restart_failed
fi

"$SYSTEMCTL_BIN" daemon-reload
"$SYSTEMCTL_BIN" reset-failed 2>/dev/null || true

# ============================================================
# Final status
# ============================================================

echo
echo "============================================================"
msg completed
echo "============================================================"

echo
msg backups

echo
msg check_result
echo
echo "  systemctl status $QUEUE_UNIT"
echo "  systemctl status $SHUTDOWN_UNIT"
echo "  systemctl status systemd-networkd.service"
echo "  ip link show $CAN_INTERFACE"
echo

# ============================================================
# FIRMWARE_RESTART before final system reboot
# ============================================================

echo
msg prepare_firmware_restart
echo

if [[ -n "$CURL_BIN" ]]; then
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

        if "$CURL_BIN"             --silent             --show-error             --fail             --max-time 15             -X POST             "$MOONRAKER_URL/printer/firmware_restart"; then

            FIRMWARE_RESTART_OK=true
            msg firmware_success
            break
        fi

        if [[ "$attempt" -lt 5 ]]; then
            msg firmware_retry
            sleep 10
        fi
    done

    if [[ "$FIRMWARE_RESTART_OK" != true ]]; then
        echo
        msg firmware_warning
    fi
else
    if [[ "$LANGUAGE" == "de" ]]; then
        echo "WARNUNG: curl wurde nicht gefunden. FIRMWARE_RESTART wird übersprungen."
        echo "Der System-Reboot wird trotzdem durchgeführt."
    else
        echo "WARNING: curl was not found. FIRMWARE_RESTART will be skipped."
        echo "The system reboot will still be performed."
    fi
fi

# ============================================================
# Final system reboot
# ============================================================

echo
msg reboot_notice
echo

# Flush pending filesystem writes before rebooting.
sync
sleep 2

if command -v systemctl >/dev/null 2>&1; then
    systemctl reboot
else
    reboot
fi
