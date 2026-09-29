## Neuestes Armbian/Debian für den Sovol SV08 mit Zero-Toolhead


> [!CAUTION]
> Diese Anleitung gilt ausschließlich für folgende Kombination:
>
> - BigTreeTech CB1 oder
> - Sovol SV08
> - UCAN-Adapter
> - Sovol Zero-Toolhead
>
> Voraussetzung ist, dass der Drucker bereits mit Mainline-Klipper unter Debian 11 funktioniert.
>
> Diese Anleitung ist nicht für einen SV08 mit der originalen Sovol-Firmware gedacht.
> Erstelle IMMER vor dem Beginn ein vollständiges Backup deiner Klipper-Konfiguration oder Speicherkarte.

### Neuestes Armbian-Image herunterladen und flashen
Lade den [Armbian Imager](https://imager.armbian.com/#downloads) herunter und starte ihn.
1. Suche nach BigTreeTech.
2. Wähle das CB1 aus.
3. Wähle ein aktuelles Minimal-Image aus.
4. Wähle die zu beschreibende SD-Karte beziehungsweise den eMMC-Speicher aus.
5. Öffne über das Zahnradsymbol die Profileinstellungen.
6. Erstelle ein neues Profil und hinterlege die folgenden Werte:

| Einstellung  | Wert |
| ------------- | ------------- |
| Profilname  | biqu  |
| Netzwerk  | WLAN-Daten des Druckers  |
| Lokalisierung | Gewünschte Sprache und passende Standardeinstellungen |
| Root-Konto | Ein sicheres, eigenes Root-Passwort |
| Erster Benutzer | biqu |
| Passwort | biqu oder ein eigenes Passwort |
| Vollständiger Name | Biqu |
| Anmelde-Shell | bash |

Wähle anschließend das erstellte Autoconfig-Profil aus und klicke auf Löschen & Flashen.

Entferne den Speicher nach Abschluss des Flashvorgangs sicher, setze ihn in den Drucker ein und startet den Drucker.

### System aktualisieren

Melde dich per SSH an und aktualisiert zunächst das System:

```
sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
```

Installiere anschließend die benötigten Pakete:

```
sudo apt install -y git python3-pip python3-serial
```
```
cd ~ && git clone https://github.com/Arksine/katapult
```

### KIAHU installieren

```
git clone https://github.com/dw-0/kiauh.git
./kiauh/kiauh.sh
```

Sobald KIAHU gestartet ist, wähle im KIAUH-Hauptmenü:
| Einstellung  | Wert |
| ------------- | ------------- |
| 1. | 1.Install |
| ------------- | ------------- |
| 1. | Klipper |
| 2. |    Moonraker |
| 3. |    Mainsail |
| 8. |    Crowsnest (am ende nicht neustarten!!!) und anschließend |
| 7. |    KlipperScreen|

> [!NOTE]
> Starte den Drucker nach der Installation von Crowsnest nicht neu sondern installiere KlipperScreen vorher. KlipperScreen macht einen automatischen Neustart.
> 
Nach dem automatischen reboot, starte KIAHU erneut und wähle 
4. Advanced aus und installiert 5. Input Shaper

### Moonraker Timelapse installieren

Installiere zunächst das Timelapse-Modul:

```
cd ~/
git clone https://github.com/mainsail-crew/moonraker-timelapse.git
cd ~/moonraker-timelapse
make install
```

Füge anschließend am Ende von der moonraker.conf Folgendes ein: (entweder über Mainsail oder über `sudo nano ~/printer_data/config/moonraker.conf`)

```
[update_manager timelapse]
type: git_repo
primary_branch: main
path: ~/moonraker-timelapse
origin: https://github.com/mainsail-crew/moonraker-timelapse.git
managed_services: klipper moonraker

[timelapse]
##   Following basic configuration is default to most images and don't need
##   to be changed in most scenarios. Only uncomment and change it if your
##   Image differ from standart installations. In most common scenarios
##   a User only need [timelapse] in their configuration.
output_path: ~/timelapse/                ##   Directory where the generated video will be saved
frame_path: /tmp/timelapse/              ##   Directory where the temporary frames are saved
ffmpeg_binary_path: /usr/bin/ffmpeg      ##   Directory where ffmpeg is installed
```
Prüfe außerdem, ob die Datei timelapse.cfg vorhanden ist und in die printer.cfg eingebunden wird:
```
[include timelapse.cfg]
```
Ohne diese Einbindung stehen die Timelapse-Makros in Klipper nicht zur Verfügung. Für Aufnahmen bei jedem Layerwechsel muss zusätzlich das Makro TIMELAPSE_TAKE_FRAME im Slicer eingefügt werden.

### Gesicherte Konfiguration wiederherstellen
Übertrage die zuvor gesicherten Konfigurationsdateien per SFTP zurück auf den Drucker.

Überprüfe insbesondere:
`printer.cfg`
`moonraker.conf`
`mainsail.cfg`
`crowsnest.conf`
weitere druckerspezifische Konfigurationsdateien

### Sovol-Erweiterungen wiederherstellen
Übertrage die beiden Dateien per SFTP in das Verzeichnis:
```
/home/biqu/klipper/klippy/extras/
```
Dateien:
```
probe_pressure.py
z_offset_calibration.py
```

Drucker jetzt neustarten

```
sudo reboot
```

> [!TIP]
> Sollte der Drucker zu irgend einem Zeitpunkt einfrieren, schalte ihn per Netzschalter einfach aus, warte 10 Sekunden und schalte ihn wieder ein. Der Fehler wird in den nächsten Schritten behoben.

### CAN-Schnittstelle dauerhaft konfigurieren

> [!TIP]
> Unter Debian 13 wird die alte Methode über /etc/network/interfaces oft ignoriert oder führt zu Fehlern. Nutze stattdessen das modernere systemd-networkd:

Erstelle die Netzwerk-Konfigurationsdatei:

```
sudo nano /etc/systemd/network/80-can0.network
```

Füge Folgendes ein:

```
[Match]
Name=can0

[Link]
TxQueueLength=128

[Network]
CAN=true

[CAN]
BitRate=1000000
```

Aktiviere und starte den Netzwerkdienst:

```
sudo systemctl enable systemd-networkd
sudo systemctl restart systemd-networkd
```

> [!TIP]
>  Das Reboot-Problem lösen (Clean Shutdown Service)
> Damit sich der UCAN-Adapter bei einem Warmstart (sudo reboot) nicht am USB-Bus des CB1 aufhängt und verschwindet (Device "can0" does not exist), muss das Kernel-Modul vor dem Neustart sauber entladen werden.

Erstelle das Shutdown-Skript:

```
sudo nano /usr/local/bin/disconnect-can.sh
```

Füge diesen Code ein:

```
#!/bin/sh
if ip link show can0 >/dev/null 2>&1; then
    /usr/sbin/ip link set can0 down
    /usr/sbin/modprobe -r gs_usb
fi
```

Mache das Skript ausführbar:

```
sudo chmod +x /usr/local/bin/disconnect-can.sh
```

Erstelle anschließend den systemd-Dienst:

```
sudo nano /etc/systemd/system/can-shutdown.service
```

Füge diesen Inhalt ein:

```
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
```

Aktiviere den Dienst:

```
sudo systemctl daemon-reload
sudo systemctl enable can-shutdown.service
sudo systemctl start can-shutdown.service
```
### qlen dauerhaft auf 128 setzen

Script anlegen
```
sudo nano /usr/local/sbin/set-can0-queue.sh
```
Inhalt:
```
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
```
Ausführbar machen:
```
sudo chmod +x /usr/local/sbin/set-can0-queue.sh
```
### systemd-Service erstellen
```
sudo nano /etc/systemd/system/set-can0-queue.service
```
Inhalt:
```
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
```
Aktivieren:
```
sudo systemctl daemon-reload
sudo systemctl enable set-can0-queue.service
sudo systemctl start set-can0-queue.service
```
Prüfen:
```
systemctl status set-can0-queue.service
ip -details link show can0
```

### Automatisches MCU update Script laden und bearbeiten
Lade das Script herunter und kopier es per sFTP in das Klipper Verzeichnis. Führ dann folgendes aus und
editiert eure MCU's rein.

```
#I'm a string, so I look like: HOSTSERIAL='XXXXXXXX'
HOSTSERIAL='38FFD9053347533826722551-if00'  # Main Board MCU  Replace with your serial number

#I'm an array so I look like: TOOLHEADUUID=('YYYYYYY')
#For multiple serials/toolheads use (mind the space in between items!): TOOLHEADUUID=('YYYYYYY1' 'YYYYYYY2' 'YYYYYYY3')
TOOLHEADUUID=('628786656b14') # ZERO TH CAN serial number from Printer.cfg --> UUID: 27ed790d8665  STOCK: 61755fe321ac  Replace with your UUID numbers
FLASHTOOLHEAD=('61755fe321ac')
```
Wenn die ID's passen, könnt ihr den 

### Webcam anpassen
Öffne dazu auf dem Drucker die crowsnest.conf und passe den Inhalt wie folgt an.

```
[cam 1]
mode: ustreamer                         # https://docs.mainsail.xyz/crowsnest/faq/backends
port: 8080                              # HTTP/MJPG stream/snapshot port
device: /dev/video1                     # See log for available devices
resolution: 1280x720                    # <width>x<height> format
max_fps: 30                             # If hardware supports it, it will be forced, otherwise ignored/coerced.
#custom_flags:                          # You can run the stream services with custom flags.
#v4l2ctl:                               # Add v4l2-ctl parameters to set up your camera, see log for your camera capabilities.
```

> [!IMPORTANT]
> ### Start Print Makro im OrcaSlicer anpassen

```
START_PRINT EXTRUDER_TEMP=[nozzle_temperature_initial_layer] BED_TEMP=[bed_temperature_initial_layer_single]
```
# Credits
Thx to [Rappetor](https://github.com/Rappetor/Sovol-SV08-Mainline), [Blenky56](https://github.com/Blenky56/Flashing-Klipper-to-Sovol-ZERO-Toolhead-on-the-SV08) and [ljg-dev](https://github.com/ljg-dev/sovol-sv08-mainline/tree/main?tab=readme-ov-file)
