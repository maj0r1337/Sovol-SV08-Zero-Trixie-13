## Cheat Sheet

CAN-Bus & Klipper-Reparatur unter Debian 13 (Trixie)
Gültig für: BigTreeTech CB1 / Sovol SV08 mit UCAN-Adapter und Sovol Zero Druckkopf

### Neustes Image runterladen und flashen
Ladet euch den Armbian Imager herunter. https://imager.armbian.com/
Startet das Programm und sucht nach BigTreeTech, wählt dann das CB1 Board aus. Nun müsst ihr das Armbian xx.x.x Minimal auswählen. Im anschluss wählt ihr den Speicher aus.

> [!TIP]
> Kleiner Tipp, klickt auf das Zahnrad oben rechts und dann auf Profiles/Profile. Erstellt ein neues Profil und füllt folgendes aus.
> Profilname: biqu
> Netzwerk: Gebt dort eure W-Lan Daten ein
> Lokalisierung: Wählt dort eure Sprache für den SV08 aus und klickt den Schieber an (Sprache anhand des Standards festlegen)
> Root-Konto: Vergebt ein root Passwort aus (sollte sicher sein, root kann alles)
> Erster Benutzer: Benutzername biqu, Passwort biqu (oder ein eigenes), Vollständiger Name Biqu, Anmelde-Shell bash

Bei Auswahl bestätigen wählt ihr unter der Übersicht das Autoconfig-Profil aus, welches wir gerade erstellt haben und klickt dann auf Löschen & Flashen

Entnehmt den Speicher, steckt ihn in den Drucker und startet diesen. Nachdem alles hochgefahren ist, installieren wir noch ein paar sachen bevor der Drucker wieder einsatzbereit ist.

Betriessystem aktualisieren

```
sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
```

Git installieren

```
sudo apt install git python3-pip -y
```

KIAHU installieren

```
git clone https://github.com/dw-0/kiauh.git
./kiauh/kiauh.sh
```

Sobald KIAHU gestartet ist, wählt ihr Install 1 aus dann installiert ihr Klipper 1, Moonraker 2, Mainsail 3, Crowsnest 8 (am ende nicht neustarten!!!) und anschließend KlipperScreen 7.
Nach dem automatischen reboot, startet ihr KIAHU erneut und wählt Advanced 4 aus und installiert Input Shaper 5.

Jetzt installiert ihr Moonraker-Timelaps

```
cd ~/
git clone https://github.com/mainsail-crew/moonraker-timelapse.git
cd ~/moonraker-timelapse
make install
```

Jetzt müssen wir die moonraker.conf anpassen. Fügt am Ende der Datei folgendes hinzu

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

Configs wiederherstellen
Jetzt spielen wir die gesicherten Configs per SFTP wieder ein und starten den Drucker neu.
Sollte der Drucker zu irgendeinem Zeitpunkt einfrieren, schalten wir ihn per Netzschalter einfach aus, warten 10 Sekunden und schalten ihn wieder ein. Den Fehler beheben wir jetzt in den nächsten Schritten.

Sovol Addons wiederherstellen
Ihr müsst die zwei Makros 'probe_pressure.py' und 'z_offset_calibration.py' in den /klipper/klippy/extras Ordner, per SFTP schieben.

Drucker jetzt neustarten

```
sudo reboot
```

1. Das CAN-Interface dauerhaft aktivieren (systemd-networkd)

Unter Debian 13 wird die alte Methode über /etc/network/interfaces oft ignoriert oder führt zu Fehlern. Nutze stattdessen das modernere systemd-networkd:

Erstelle die Netzwerk-Konfigurationsdatei:

```
sudo nano /etc/systemd/network/80-can0.network
```

Füge folgenden Inhalt ein (wichtig für die strikte Trennung von Bitrate und Queue-Länge unter Debian 13):
text

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

2. Das Reboot-Problem lösen (Clean Shutdown Service)
Damit sich der UCAN-Adapter bei einem Warmstart (sudo reboot) nicht am USB-Bus des CB1 aufhängt und verschwindet (Device "can0" does not exist), muss das Kernel-Modul vor dem Neustart sauber entladen werden.

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

Mach das Skript ausführbar:

```
sudo chmod +x /usr/local/bin/disconnect-can.sh
```

Erstelle den passenden systemd-Dienst, der dieses Skript exakt beim Herunterfahren triggert:
bash

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

Lade systemd neu, aktiviere und starte den Dienst:

```
sudo systemctl daemon-reload
sudo systemctl enable can-shutdown.service
sudo systemctl start can-shutdown.service
```

Katapult und pyserialinstallieren um die MCU's zu flashen

```
cd ~ && git clone https://github.com/Arksine/katapult
```
```
pip3 install pyserial
```

Automatisches MCU update Script laden und bearbeiten
Ladet das Script runter und kopiert es per sFTP in das Klipper Verzeichnis. Führt dann folgendes aus und
editiert eure MCU's rein.

```
#I'm a string, so I look like: HOSTSERIAL='XXXXXXXX'
HOSTSERIAL='38FFD9053347533826722551-if00'  # Main Board MCU  Replace with your serial number

#I'm an array so I look like: TOOLHEADUUID=('YYYYYYY')
#For multiple serials/toolheads use (mind the space in between items!): TOOLHEADUUID=('YYYYYYY1' 'YYYYYYY2' 'YYYYYYY3')
TOOLHEADUUID=('628786656b14') # ZERO TH CAN serial number from Printer.cfg --> UUID: 27ed790d8665  STOCK: 61755fe321ac  Replace with your UUID numbers
FLASHTOOLHEAD=('61755fe321ac')
```

Webcam anpassen
Öffnet dazu auf dem Drucker die crowsnest.conf und passt bei [cam1] das device auf /dev/video1 an

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

Start Print Makro im OrcaSlicer anpassen

```
START_PRINT EXTRUDER_TEMP=[nozzle_temperature_initial_layer] BED_TEMP=[bed_temperature_initial_layer_single]
```
