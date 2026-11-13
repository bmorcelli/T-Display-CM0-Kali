#!/usr/bin/env bash
# Configure a Wayland-only login (greetd + gtkgreet + cage) running Xfce
# under labwc with software rendering, for the CM0 AMOLED panel. Validated
# in diagnostics/trixie-port-20261112 (30 Hz panel driver, WLR_RENDERER=pixman).
#
# Xorg does not render on this panel/driver combination (confirmed by
# physical black-screen tests of both the lightdm GTK greeter and startx/Xfce,
# see diagnostics/STARTX-VALIDATION.md and the trixie-port README), so the
# login screen and desktop both have to be pure Wayland/labwc.
#
# Raspberry Pi OS ships its own PIXEL/labwc desktop and login, so this only
# applies to Kali. install_lilygo_cm0_lite.sh only installs kernel
# modules/overlays and is distro-agnostic; it does not touch the desktop
# session, so this script is a separate, idempotent step.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEB_DIR="${SCRIPT_DIR}/debs"

log() { echo "[kali-wayland-desktop] $*"; }

. /etc/os-release 2>/dev/null || true
if [[ "${ID:-}" != "kali" ]]; then
    log "not Kali (ID=${ID:-unknown}), nothing to do"
    exit 0
fi

if ! command -v startxfce4 >/dev/null 2>&1; then
    log "startxfce4 not found (no Xfce installed), nothing to do"
    exit 0
fi

TARGET_USER=$(getent passwd | awk -F: '$3>=1000 && $3<60000 {print $1; exit}')
if [[ -z "${TARGET_USER:-}" ]]; then
    log "no regular (uid>=1000) user found, nothing to do"
    exit 0
fi
TARGET_HOME=$(getent passwd "${TARGET_USER}" | cut -d: -f6)
log "target user: ${TARGET_USER} (${TARGET_HOME})"

PANEL_OUTPUT="DSI-1"
OUTPUT_TRANSFORM=90                 # landscape, confirmed visually on-device
OUTPUT_SCALE=1.5                    # UI size on a panel this small; 2x cuts off/decenters content
TOUCH_CALIBRATION="0 -1 1 1 0 0"    # matches wl_output transform=90 (90 deg cw)

install_packages() {
    local pkgs=(greetd gtkgreet cage python3-evdev)
    local missing=()
    local pkg
    for pkg in "${pkgs[@]}"; do
        dpkg -s "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
    done
    if [[ "${#missing[@]}" -eq 0 ]]; then
        log "greetd/gtkgreet/cage/python3-evdev already installed"
        return 0
    fi

    log "installing: ${missing[*]}"
    export DEBIAN_FRONTEND=noninteractive
    if [[ -d "${DEB_DIR}" ]] && ls "${DEB_DIR}"/*.deb >/dev/null 2>&1; then
        log "installing bundled .deb packages from ${DEB_DIR} (offline)"
        if ! dpkg -i "${DEB_DIR}"/*.deb; then
            log "dpkg -i reported missing dependencies, running apt-get -f install"
            apt-get -f install -y
        fi
    else
        log "no bundled .deb packages found, falling back to apt-get install (needs network)"
        apt-get install -y --no-install-recommends "${missing[@]}"
    fi

    for pkg in "${pkgs[@]}"; do
        dpkg -s "${pkg}" >/dev/null 2>&1 || {
            log "ERROR: ${pkg} still not installed"
            return 1
        }
    done
}

write_greeter_files() {
    install -d -m 0755 /usr/local/bin
    cat > /usr/local/bin/cage-greeter.sh <<EOF
#!/bin/sh
# Greeter compositor for greetd. Rotates the panel right after cage's
# Wayland socket appears, so the login screen matches the Xfce session
# rotation without a visible portrait flash lasting more than one frame.
export WLR_RENDERER=pixman
export XDG_RUNTIME_DIR="\${XDG_RUNTIME_DIR:-/run/user/\$(id -u)}"
cage -s -- gtkgreet -x -s /etc/greetd/gtkgreet.css -c "env WLR_RENDERER=pixman startxfce4 --wayland" &
CAGE_PID=\$!
for i in \$(seq 1 50); do
    if [ -S "\${XDG_RUNTIME_DIR}/wayland-0" ]; then
        WAYLAND_DISPLAY=wayland-0 wlr-randr --output ${PANEL_OUTPUT} --transform ${OUTPUT_TRANSFORM} --scale ${OUTPUT_SCALE} >/dev/null 2>&1
        break
    fi
    sleep 0.1
done
wait "\${CAGE_PID}"
EOF
    chmod 0755 /usr/local/bin/cage-greeter.sh

    install -d -m 0755 /etc/greetd
    cat > /etc/greetd/config.toml <<EOF
[terminal]
vt = 7

[default_session]
command = "/usr/local/bin/cage-greeter.sh"
user = "_greetd"
EOF

    # Single entry on purpose: with -x (--disable-custom-commands) gtkgreet
    # still renders a session combo box when more than one line is listed
    # here. One line plus the CSS below keeps the login screen to just
    # username/password.
    cat > /etc/greetd/environments <<EOF
env WLR_RENDERER=pixman startxfce4 --wayland
EOF

    cat > /etc/greetd/gtkgreet.css <<'EOF'
#command-selector {
    opacity: 0;
    min-width: 0;
    min-height: 0;
    margin: 0;
    padding: 0;
    border: none;
}
EOF

    install -d -m 0755 /usr/share/wayland-sessions
    cat > /usr/share/wayland-sessions/xfce-cm0.desktop <<'EOF'
[Desktop Entry]
Name=Xfce (CM0 pixman)
Comment=Xfce on Wayland/labwc with software rendering for the T-Display CM0 AMOLED panel
Exec=env WLR_RENDERER=pixman startxfce4 --wayland
Icon=
Type=Application
DesktopNames=XFCE
EOF

    cat > /usr/share/wayland-sessions/labwc-cm0.desktop <<'EOF'
[Desktop Entry]
Name=labwc (CM0 pixman)
Comment=labwc with software rendering for the T-Display CM0 AMOLED panel
Exec=env WLR_RENDERER=pixman labwc
Icon=labwc
Type=Application
DesktopNames=labwc;wlroots
EOF
}

enable_greetd() {
    if systemctl list-unit-files lightdm.service >/dev/null 2>&1; then
        systemctl disable --now lightdm >/dev/null 2>&1 || true
    fi
    systemctl enable greetd
    systemctl set-default graphical.target
    log "greetd enabled, default.target=graphical.target"
}

configure_labwc_session() {
    local labwc_dir="${TARGET_HOME}/.config/xfce4/labwc"
    install -d -m 0755 -o "${TARGET_USER}" -g "${TARGET_USER}" "${labwc_dir}"

    if [[ ! -f "${labwc_dir}/rc.xml" ]]; then
        cp -p /usr/share/xfce4/labwc/labwc-rc.xml "${labwc_dir}/rc.xml"
    fi
    if [[ ! -f "${labwc_dir}/environment" ]]; then
        cp -p /usr/share/xfce4/labwc/labwc-environment "${labwc_dir}/environment"
    fi

    if ! grep -q 'calibrationMatrix' "${labwc_dir}/rc.xml"; then
        python3 - "${labwc_dir}/rc.xml" "${TOUCH_CALIBRATION}" <<'PY'
import sys
path, matrix = sys.argv[1], sys.argv[2]
text = open(path).read()
block = (
    '  <libinput>\n'
    '    <device category="touch">\n'
    f'      <calibrationMatrix>{matrix}</calibrationMatrix>\n'
    '    </device>\n'
    '  </libinput>\n\n'
)
text = text.replace('</labwc_config>', block + '</labwc_config>')
open(path, 'w').write(text)
PY
    fi

    cat > "${labwc_dir}/autostart" <<EOF
#!/bin/sh
# Runs as part of labwc startup, before xfce4-session draws anything, so
# the desktop comes up already rotated instead of flashing portrait first.
wlr-randr --output ${PANEL_OUTPUT} --transform ${OUTPUT_TRANSFORM} --scale ${OUTPUT_SCALE} &
EOF
    chmod 0755 "${labwc_dir}/autostart"

    chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.config/xfce4"
}

install_touch_as_touchpad() {
    # libinput has no touchpad-emulation mode for touch hardware, and
    # forcing this digitizer's udev ID_INPUT_TOUCHPAD property makes it
    # stop responding entirely (tested on-device) - there is no compositor
    # or libinput-level way to do this. Instead, a small daemon grabs the
    # touchscreen's evdev node exclusively and drives a virtual relative
    # mouse from it: drag to move the pointer, one-finger tap to left
    # click, two-finger tap to right click. Grabbing makes the real
    # touchscreen invisible to the compositor, so it never also jumps the
    # pointer to the absolute touch position.
    install -m 0755 "${SCRIPT_DIR}/touch-as-touchpad.py" /usr/local/bin/cm0-touch-as-touchpad.py

    cat > /etc/systemd/system/cm0-touch-as-touchpad.service <<EOF
[Unit]
Description=CM0 touchscreen-as-touchpad relative pointer daemon
After=local-fs.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/cm0-touch-as-touchpad.py
Restart=on-failure
RestartSec=1

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable --now cm0-touch-as-touchpad.service
}

install_packages
write_greeter_files
enable_greetd
configure_labwc_session
install_touch_as_touchpad

log "done"
