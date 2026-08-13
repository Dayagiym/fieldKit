#!/usr/bin/env bash
#
# Mint FieldKit installer
#
# Foundation script for Linux Mint 22.3 MATE.
# This first version intentionally performs validation and logging only.
# Package removal and field-tool installation will be added incrementally.
#

set -Eeuo pipefail

readonly SCRIPT_NAME="Mint FieldKit"
readonly LOG_DIR="${HOME}/.local/state/fieldkit"
readonly LOG_FILE="${LOG_DIR}/install.log"

mkdir -p "${LOG_DIR}"

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "${LOG_FILE}"
}

fail() {
    log "ERROR: $*"
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

log "Starting ${SCRIPT_NAME} installer."

[[ "${EUID}" -eq 0 ]] && fail "Do not run this script as root. Run it as your normal user; sudo will be requested when needed."

require_command sudo
require_command lsb_release
require_command apt-get

if [[ "$(lsb_release -is)" != "Linuxmint" ]]; then
    fail "This installer is intended for Linux Mint. Detected: $(lsb_release -is)"
fi

mint_release="$(lsb_release -rs)"
if [[ "${mint_release}" != "22.3" ]]; then
    fail "This version targets Linux Mint 22.3. Detected: ${mint_release}"
fi

if [[ "${XDG_CURRENT_DESKTOP:-}" != *MATE* && "${XDG_CURRENT_DESKTOP:-}" != *MATE:* ]]; then
    log "WARNING: MATE desktop was not detected from XDG_CURRENT_DESKTOP='${XDG_CURRENT_DESKTOP:-unset}'."
fi

log "Validated Linux Mint ${mint_release}."
log "FieldKit installer foundation completed successfully."
log "No packages were removed or installed by this version."
