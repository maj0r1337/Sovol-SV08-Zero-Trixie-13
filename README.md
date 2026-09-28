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
> Erstellt IMMER vor dem Beginn ein vollständiges Backup eurer Klipper-Konfiguration oder Speicherkarte.

### Neuestes Armbian-Image herunterladen und flashen
Ladet den [Armbian Imager](https://imager.armbian.com/#downloads) herunter und startet ihn.
1. Sucht nach BigTreeTech.
2. Wählt das CB1 aus.
3. Wählt ein aktuelles Minimal-Image aus.
4. Wählt die zu beschreibende SD-Karte beziehungsweise den eMMC-Speicher aus.
5. Öffnet über das Zahnradsymbol die Profileinstellungen.
6. Erstellt ein neues Profil und hinterlegt die folgenden Werte:

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

Wählt anschließend das erstellte Autoconfig-Profil aus und klickt auf Löschen & Flashen.

Entfernt den Speicher nach Abschluss des Flashvorgangs sicher, setzt ihn in den Drucker ein und startet den Drucker.

### System aktualisieren

Meldet euch per SSH an und aktualisiert zunächst das System:

```
sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
```

Installiert anschließend die benötigten Pakete:

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

Sobald KIAHU gestartet ist, wählt im KIAUH-Hauptmenü:
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
> Startet den Drucker nach der Installation von Crowsnest nicht neu sondern installiert KlipperScreen vorher. KlipperScreen macht einen automatischen Neustart.
> 
Nach dem automatischen reboot, startet ihr KIAHU erneut und wählt 
4. Advanced aus und installiert 5. Input Shaper

### Moonraker Timelapse installieren

Installiert zunächst das Timelapse-Modul:

```
cd ~/
git clone https://github.com/mainsail-crew/moonraker-timelapse.git
cd ~/moonraker-timelapse
make install
```

Fügt anschließend am Ende von moonraker.conf Folgendes ein: (entweder über Mainsail oder über `sudo nano ~/printer_data/config/moonraker.conf`)

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
Prüft außerdem, ob die Datei timelapse.cfg vorhanden ist und in printer.cfg eingebunden wird:
```
[include timelapse.cfg]
```
Ohne diese Einbindung stehen die Timelapse-Makros in Klipper nicht zur Verfügung. Für Aufnahmen bei jedem Layerwechsel muss zusätzlich das Makro TIMELAPSE_TAKE_FRAME im Slicer eingefügt werden.

### Gesicherte Konfiguration wiederherstellen
Übertragt die zuvor gesicherten Konfigurationsdateien per SFTP zurück auf den Drucker.

Überprüft insbesondere:
`printer.cfg`
`moonraker.conf`
`mainsail.cfg`
`crowsnest.conf`
weitere druckerspezifische Konfigurationsdateien



### Sovol-Erweiterungen wiederherstellen
Übertragt die beiden Dateien per SFTP in das Verzeichnis:
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
> Sollte der Drucker zu irgendeinem Zeitpunkt einfrieren, schalten wir ihn per Netzschalter einfach aus, warten 10 Sekunden und schalten ihn wieder ein. Den Fehler beheben wir jetzt in den nächsten Schritten.

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

Aktiviert den Dienst:

```
sudo systemctl daemon-reload
sudo systemctl enable can-shutdown.service
sudo systemctl start can-shutdown.service
```

### Automatisches MCU update Script laden und bearbeiten
Lade das Script herunter und kopiert es per sFTP in das Klipper Verzeichnis. Führt dann folgendes aus und
editiert eure MCU's rein.

```
#I'm a string, so I look like: HOSTSERIAL='XXXXXXXX'
HOSTSERIAL='38FFD9053347533826722551-if00'  # Main Board MCU  Replace with your serial number

#I'm an array so I look like: TOOLHEADUUID=('YYYYYYY')
#For multiple serials/toolheads use (mind the space in between items!): TOOLHEADUUID=('YYYYYYY1' 'YYYYYYY2' 'YYYYYYY3')
TOOLHEADUUID=('628786656b14') # ZERO TH CAN serial number from Printer.cfg --> UUID: 27ed790d8665  STOCK: 61755fe321ac  Replace with your UUID numbers
FLASHTOOLHEAD=('61755fe321ac')
```

### Webcam anpassen
Öffnet dazu auf dem Drucker die crowsnest.conf und passt den Inhalt wie folgt an.

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
