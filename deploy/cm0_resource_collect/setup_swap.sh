#!/bin/bash
# Called by lilygo-firstboot-install.service before installing the resources.
set -Eeuo pipefail

SWAP_FILE="/swapfile"
FSTAB="/etc/fstab"
SWAP_BYTES=1073741824
TEMP_FILE=""

log() { echo "[cm0-swap] $*"; }
fail() { log "ERROR: $*" >&2; exit 1; }
cleanup() { [ -z "${TEMP_FILE}" ] || rm -f -- "${TEMP_FILE}"; }
trap cleanup EXIT

[[ ${EUID} -eq 0 ]] || fail 'Execute with root privileges.'
for tool in dd df awk stat blkid mkswap swapon mktemp; do
    command -v "${tool}" >/dev/null || fail "Required command missing: ${tool}"
done
[[ -f "${FSTAB}" ]] || fail "Missing ${FSTAB}"

# Reject conflicting entries before allocating a file or activating swap.
awk -v path="${SWAP_FILE}" '
    $1 == path && ($3 != "swap" || $4 ~ /(^|,)noauto(,|$)/) { bad=1 }
    END { exit bad }
' "${FSTAB}" || fail "Conflicting ${SWAP_FILE} entry in ${FSTAB}"

if [[ -e "${SWAP_FILE}" || -L "${SWAP_FILE}" ]]; then
    [[ -f "${SWAP_FILE}" && ! -L "${SWAP_FILE}" ]] || fail "${SWAP_FILE} must be a regular file, not a symlink."
    [[ $(stat -c %s "${SWAP_FILE}") -eq ${SWAP_BYTES} ]] || fail "Existing ${SWAP_FILE} is not 1 GiB; refusing to overwrite it."
    [[ $(blkid -p -s TYPE -o value "${SWAP_FILE}") == swap ]] || fail "Existing ${SWAP_FILE} is not formatted as swap; refusing to overwrite it."
    log 'Reusing existing 1 GiB swap file.'
else
    # Keep at least 64 MiB available for boot logs and installation metadata.
    available_kib=$(df -Pk / | awk 'END { print $4 }')
    [[ ${available_kib} =~ ^[0-9]+$ ]] || fail 'Cannot determine free disk space.'
    (( available_kib >= SWAP_BYTES / 1024 + 65536 )) || fail 'At least 1088 MiB of free disk space is required.'
    umask 077
    TEMP_FILE=$(mktemp "${SWAP_FILE}.cm0-XXXXXX")
    log 'Allocating 1 GiB of swap; this may take a while on a microSD card.'
    # dd allocates real blocks: no sparse files or filesystem-dependent fallocate.
    dd if=/dev/zero of="${TEMP_FILE}" bs=1M count=1024 conv=fsync status=none
    chmod 0600 "${TEMP_FILE}"
    mkswap "${TEMP_FILE}"
    mv -T -- "${TEMP_FILE}" "${SWAP_FILE}"
    TEMP_FILE=""
fi

chown root:root "${SWAP_FILE}"
chmod 0600 "${SWAP_FILE}"
if swapon --show=NAME --noheadings --raw | awk -v path="${SWAP_FILE}" '$0 == path { found=1 } END { exit !found }'; then
    log 'Swap is already active.'
else
    swapon "${SWAP_FILE}"
fi

if ! awk -v path="${SWAP_FILE}" '$1 == path && $3 == "swap" { found=1 } END { exit !found }' "${FSTAB}"; then
    cp -a "${FSTAB}" "${FSTAB}.before-cm0-swap"
    printf '\n# CM0: 1 GiB swap configured on first boot\n%s none swap sw 0 0\n' "${SWAP_FILE}" >> "${FSTAB}"
fi
log "Ready: ${SWAP_FILE}, 1 GiB, enabled now and in ${FSTAB} for future boots."
