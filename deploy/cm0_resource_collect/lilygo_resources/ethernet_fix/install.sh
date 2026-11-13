#!/usr/bin/env bash
# Reapply the tested CM0 USB full-speed workaround without replacing root=.
set -Eeuo pipefail
[[ $EUID == 0 ]] || { echo 'Execute com sudo.' >&2; exit 1; }
model=$(tr -d '\0' </proc/device-tree/model)
[[ $model == *'Compute Module 0'* ]] || { echo "Modelo inesperado: $model" >&2; exit 1; }
boot=/boot/firmware
[[ -f $boot/config.txt && -f $boot/cmdline.txt ]] || exit 1
command -v nmcli >/dev/null
command -v python3 >/dev/null
backup=/var/backups/cm0-ethernet-$(date +%Y%m%d-%H%M%S)
install -d -m 0700 "$backup"
cp -a "$boot/config.txt" "$boot/cmdline.txt" "$backup/"
cp -a /etc/NetworkManager/system-connections "$backup/"
python3 - "$boot" <<'PY'
import os, pathlib, re, sys, tempfile
boot=pathlib.Path(sys.argv[1])
config=boot/'config.txt'
section='all'
lines=[]
for line in config.read_text().splitlines():
    text=line.split('#',1)[0].strip()
    if text.startswith('['):
        section=text.strip('[]').lower()
    if section in ('all','cm0') and re.match(r'dtoverlay=(?:dwc2|cm0-usb-full-speed)(?:,|$)',text):
        line='# Disabled by CM0 Ethernet workaround: '+line
    lines.append(line)
marker='# CM0 Ethernet: internal USB at 12 Mbit/s using dwc_otg.speed=1'
if marker not in lines:
    lines+=['', '[all]', marker]
cmdline=boot/'cmdline.txt'
tokens=cmdline.read_text().split()
if not any(x.startswith('root=') for x in tokens):
    raise RuntimeError('cmdline.txt sem root=: nenhuma alteração aplicada')
tokens=[x for x in tokens if not x.startswith('dwc_otg.speed=')]
tokens.append('dwc_otg.speed=1')
for path,content in ((config,'\n'.join(lines)+'\n'),(cmdline,' '.join(tokens)+'\n')):
    fd,tmp=tempfile.mkstemp(prefix=path.name+'.cm0-',dir=boot)
    try:
        with os.fdopen(fd,'w') as f:
            f.write(content); f.flush(); os.fsync(f.fileno())
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
PY
serial=$(awk '/^Serial/ {print $3}' /proc/cpuinfo)
[[ $serial =~ ^[[:xdigit:]]{16}$ ]] || { echo 'Serial da CPU inválido.' >&2; exit 1; }
suffix=${serial: -6}
mac="02:b8:27:${suffix:0:2}:${suffix:2:2}:${suffix:4:2}"
profile=CM0-Ethernet
if ! nmcli connection show "$profile" >/dev/null 2>&1; then
    nmcli connection add type ethernet ifname eth0 con-name "$profile"
fi
nmcli connection modify "$profile" connection.interface-name eth0 \
    connection.autoconnect yes connection.autoconnect-priority 100 \
    ipv4.method auto ipv4.route-metric 100 ipv6.method auto ipv6.route-metric 100 \
    802-3-ethernet.cloned-mac-address "$mac"
sync
echo "Configuração salva. Backup: $backup"
echo 'Reinicie com sudo reboot. O Wi-Fi permanece disponível.'
