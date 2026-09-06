#!/usr/bin/env bash
# Mint FieldKit installer
# Interactive package selection for Linux Mint 22.3 MATE or Cinnamon.
set -Eeuo pipefail

readonly SCRIPT_NAME="Mint FieldKit"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/../config/packages.conf"
readonly LOG_DIR="${HOME}/.local/state/fieldkit"
readonly LOG_FILE="${LOG_DIR}/install.log"
readonly WIFIMAN_DOWNLOAD_URL="https://desktop.wifiman.com/wifiman-desktop-1.1.3-amd64.deb"
readonly DRAWIO_RELEASE_API="https://api.github.com/repos/jgraph/drawio-desktop/releases/latest"
readonly NEXTCLOUD_RELEASE_URL="https://download.nextcloud.com/desktop/releases/Linux/"
readonly CHIRP_RELEASE_BASE_URL="https://archive.chirpmyradio.com/chirp_next/"

DRY_RUN=false
TEMP_DIRS=()
mkdir -p "${LOG_DIR}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "${LOG_FILE}"; }
fail() { log "ERROR: $*"; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }
cleanup_temp_dirs() { local dir; for dir in "${TEMP_DIRS[@]}"; do [[ -n "${dir}" && -d "${dir}" ]] && rm -rf -- "${dir}"; done; }
trap cleanup_temp_dirs EXIT
new_temp_dir() { local dir; dir="$(mktemp -d)" || fail "Unable to create a temporary directory."; TEMP_DIRS+=("${dir}"); printf '%s\n' "${dir}"; }

usage() { cat <<'EOF'
Usage: fieldkit-install.sh [--dry-run]

  --dry-run     Show package choices and planned changes without modifying the system.
  -h, --help    Show this help.
EOF
}
while [[ $# -gt 0 ]]; do case "$1" in --dry-run) DRY_RUN=true ;; -h|--help) usage; exit 0 ;; *) fail "Unknown option: $1" ;; esac; shift; done

log "Starting ${SCRIPT_NAME} installer."
[[ "${EUID}" -eq 0 ]] && fail "Do not run this script as root. Run it as your normal user; sudo will be requested when needed."
require_command sudo; require_command lsb_release; require_command apt-get; require_command apt-cache; require_command dpkg-query
[[ -f "${CONFIG_FILE}" ]] || fail "Package catalog not found: ${CONFIG_FILE}"
[[ "$(lsb_release -is)" == "Linuxmint" ]] || fail "This installer is intended for Linux Mint. Detected: $(lsb_release -is)"
mint_release="$(lsb_release -rs)"
[[ "${mint_release}" == "22.3" ]] || fail "This version targets Linux Mint 22.3. Detected: ${mint_release}"
case "${XDG_CURRENT_DESKTOP:-}" in
    *MATE*|*MATE:*|*Cinnamon*|*CINNAMON*|X-Cinnamon|X-Cinnamon:*) ;;
    *) log "WARNING: MATE or Cinnamon desktop was not detected from XDG_CURRENT_DESKTOP='${XDG_CURRENT_DESKTOP:-unset}'." ;;
esac
log "Validated Linux Mint ${mint_release}."

is_installed() { local package="$1"; [[ "$(dpkg-query -W -f='${Status}' "${package}" 2>/dev/null || true)" == "install ok installed" ]]; }
apt_package_available() { local package="$1"; apt-cache show "${package}" >/dev/null 2>&1; }
install_apt_packages() { local operation="$1"; shift; local -a packages=("$@"); [[ "${#packages[@]}" -gt 0 ]] || return 0; if [[ "${operation}" == install ]]; then sudo apt-get install -y -- "${packages[@]}"; else sudo apt-get remove --purge -y -- "${packages[@]}"; fi; }

ubuntu_codename() {
    local codename="${UBUNTU_CODENAME:-}"
    if [[ -z "${codename}" && -r /etc/os-release ]]; then . /etc/os-release; codename="${UBUNTU_CODENAME:-}"; fi
    printf '%s\n' "${codename}"
}

setup_tailscale_repository() {
    if is_installed tailscale || apt_package_available tailscale; then return 0; fi
    [[ "${DRY_RUN}" == true ]] && { log "DRY RUN: Tailscale external source detected; it will be available during a real run."; return 0; }
    if ! command -v curl >/dev/null 2>&1; then log "curl is required to configure Tailscale; installing curl first."; install_apt_packages install curl; fi
    local ubuntu_codename="$(ubuntu_codename)"
    [[ -n "${ubuntu_codename}" ]] || fail "Unable to determine the Ubuntu base codename required for the Tailscale repository."
    case "${ubuntu_codename}" in noble|jammy|focal|bionic|xenial) ;; *) fail "Unsupported Ubuntu base '${ubuntu_codename}' for the Tailscale repository." ;; esac
    log "Configuring the official Tailscale APT repository for Ubuntu ${ubuntu_codename}."
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 120 "https://pkgs.tailscale.com/stable/ubuntu/${ubuntu_codename}.noarmor.gpg" | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 120 "https://pkgs.tailscale.com/stable/ubuntu/${ubuntu_codename}.tailscale-keyring.list" | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
    sudo apt-get update
}

load_catalog() {
    REMOVE_PACKAGES=(); REMOVE_NAMES=(); REMOVE_RECS=(); REMOVE_REASONS=(); REMOVE_SOURCES=(); REMOVE_STATES=()
    INSTALL_PACKAGES=(); INSTALL_NAMES=(); INSTALL_RECS=(); INSTALL_REASONS=(); INSTALL_SOURCES=(); INSTALL_STATES=()
    while IFS='|' read -r action package name recommendation reason source; do
        [[ -z "${action}" || "${action}" == \#* ]] && continue
        case "${action}" in
            remove) if is_installed "${package}"; then REMOVE_PACKAGES+=("${package}"); REMOVE_NAMES+=("${name}"); REMOVE_RECS+=("${recommendation}"); REMOVE_REASONS+=("${reason}"); REMOVE_SOURCES+=("${source}"); REMOVE_STATES+=("INSTALLED"); fi ;;
            install)
                INSTALL_PACKAGES+=("${package}"); INSTALL_NAMES+=("${name}"); INSTALL_RECS+=("${recommendation}"); INSTALL_REASONS+=("${reason}"); INSTALL_SOURCES+=("${source}")
                if is_installed "${package}"; then INSTALL_STATES+=("INSTALLED")
                elif [[ "${source}" == external:* ]]; then
                    if [[ "${package}" == "wifiman" && "$(ubuntu_codename)" == "noble" ]]; then INSTALL_STATES+=("UNSUPPORTED"); else INSTALL_STATES+=("EXTERNAL"); fi
                elif apt_package_available "${package}"; then INSTALL_STATES+=("AVAILABLE")
                else INSTALL_STATES+=("UNAVAILABLE"); fi
                ;;
            *) fail "Invalid action '${action}' in ${CONFIG_FILE}" ;;
        esac
    done < "${CONFIG_FILE}"
}

validate_catalog() {