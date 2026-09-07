#!/usr/bin/env bash
# Mint FieldKit installer
# Interactive package selection for Linux Mint 22.3 or 23 MATE or Cinnamon.
set -Eeuo pipefail

readonly SCRIPT_NAME="Mint FieldKit"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly CONFIG_FILE="${SCRIPT_DIR}/../config/packages.conf"
readonly LOG_DIR="${HOME}/.local/state/fieldkit"
readonly LOG_FILE="${LOG_DIR}/install.log"
readonly WIFIMAN_DOWNLOAD_URL="https://desktop.wifiman.com/wifiman-desktop-1.1.3-amd64.deb"
readonly DRAWIO_RELEASE_API="https://api.github.com/repos/jgraph/drawio-desktop/releases/latest"
readonly NEXTCLOUD_RELEASE_URL="https://download.nextcloud.com/desktop/releases/Linux/"
readonly CHIRP_GIT_URL="https://github.com/kk7ds/chirp.git"

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
case "${mint_release}" in
    22.3) log "Validated Linux Mint 22.3 (supported/tested baseline)." ;;
    23*) log "WARNING: Linux Mint ${mint_release} is supported/testing. Mint 23 is based on Ubuntu 26.04; external packages and ZFS tooling should be validated on the target system before production deployment." ;;
    *) fail "This version supports Linux Mint 22.3 and 23.x. Detected: ${mint_release}" ;;
esac
desktop_detected=false
for desktop_value in "${XDG_CURRENT_DESKTOP:-}" "${XDG_SESSION_DESKTOP:-}" "${DESKTOP_SESSION:-}"; do
    case "${desktop_value}" in
        *MATE*|*MATE:*|*Cinnamon*|*CINNAMON*|X-Cinnamon|X-Cinnamon:*) desktop_detected=true; break ;;
    esac
done
if [[ "${desktop_detected}" == false ]] && pgrep -x cinnamon >/dev/null 2>&1; then
    desktop_detected=true
fi
[[ "${desktop_detected}" == true ]] || log "WARNING: MATE or Cinnamon desktop was not detected from the current session environment."

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
    case "${ubuntu_codename}" in noble|resolute|jammy|focal|bionic|xenial) ;; *) fail "Unsupported Ubuntu base '${ubuntu_codename}' for the Tailscale repository." ;; esac
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
                    if [[ "${package}" == "wifiman" && "$(ubuntu_codename)" =~ ^(noble|resolute)$ ]]; then INSTALL_STATES+=("UNSUPPORTED"); else INSTALL_STATES+=("EXTERNAL"); fi
                elif apt_package_available "${package}"; then INSTALL_STATES+=("AVAILABLE")
                else INSTALL_STATES+=("UNAVAILABLE"); fi
                ;;
            *) fail "Invalid action '${action}' in ${CONFIG_FILE}" ;;
        esac
    done < "${CONFIG_FILE}"
}
validate_catalog() {
    local line_number=0 line action package name recommendation reason source extra
    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1)); [[ -z "${line}" || "${line}" == \#* ]] && continue
        IFS='|' read -r action package name recommendation reason source extra <<< "${line}"
        [[ -z "${action}" || -z "${package}" || -z "${name}" || -z "${recommendation}" || -z "${reason}" || -z "${source}" || -n "${extra}" ]] && fail "Malformed package catalog entry at ${CONFIG_FILE}:${line_number}"
        case "${action}" in install|remove) ;; *) fail "Invalid action '${action}' at ${CONFIG_FILE}:${line_number}" ;; esac
        case "${source}" in apt|external:*) ;; *) fail "Invalid source '${source}' at ${CONFIG_FILE}:${line_number}" ;; esac
        [[ "${package}" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || fail "Invalid package name '${package}' at ${CONFIG_FILE}:${line_number}"
    done < "${CONFIG_FILE}"
}
contains_number() { local needle="$1"; shift; local value; for value in "$@"; do [[ "${value}" == "${needle}" ]] && return 0; done; return 1; }

dry_run_external_package() {
    case "$1" in
        tailscale) log "DRY RUN: would configure the official Tailscale APT repository and install Tailscale." ;;
        wifiman) log "DRY RUN: WiFiman Desktop is skipped on Linux Mint ${mint_release} because the stable Ubiquiti 1.1.3 package requires libwebkit2gtk-4.0-37, which is not available on the Ubuntu base used by current supported FieldKit releases." ;;
        drawio) log "DRY RUN: would resolve the latest official draw.io Desktop AMD64 package from GitHub and install it." ;;
        nextcloud) log "DRY RUN: would download the latest official Nextcloud Desktop x86_64 AppImage and install it for the current user." ;;
        chirp) log "DRY RUN: would install CHIRP dependencies and install CHIRP-next from the official CHIRP Git repository with pipx." ;;
        *) fail "No external installer is defined for package '$1'." ;;
    esac
}
require_amd64() { [[ "$(dpkg --print-architecture)" == amd64 ]] || fail "$1 currently requires an amd64/x86_64 system."; }

require_downloaded_file() {
    local file="$1" description="$2"
    [[ -s "${file}" ]] || fail "${description} download is empty or missing."
    require_command file
    file "${file}" | grep -qiE 'Debian binary package|ELF|Zip archive|Python wheel|POSIX shell script|application' || log "WARNING: downloaded ${description} has an unexpected file type; continuing to installer validation."
}

curl_download() {
    local url="$1" output="$2" description="$3"
    log "Downloading ${description}."
    curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 120 -o "${output}" -- "${url}"
}

install_external_package() {
    local package="$1"
    case "${package}" in
        tailscale) log "Installing Tailscale from its configured official APT repository."; install_apt_packages install tailscale ;;
        wifiman)
            if [[ "$(ubuntu_codename)" =~ ^(noble|resolute)$ ]]; then
                log "WARNING: Skipping WiFiman Desktop on Linux Mint ${mint_release}. Ubiquiti's stable Linux package 1.1.3 requires libwebkit2gtk-4.0-37, which is unavailable on the Ubuntu base. FieldKit will not install an unreleased vendor package automatically."
                return 0
            fi
            require_amd64 "WiFiman Desktop"; require_command curl
            local temp_dir deb_file; temp_dir="$(new_temp_dir)"; deb_file="${temp_dir}/wifiman-desktop.deb"
            curl_download "${WIFIMAN_DOWNLOAD_URL}" "${deb_file}" "the official Ubiquiti WiFiman Desktop Linux package"
            require_downloaded_file "${deb_file}" "WiFiman Desktop"; log "Installing WiFiman Desktop."; sudo apt-get install -y -- "${deb_file}"
            ;;
        drawio)
            require_amd64 "draw.io Desktop"; require_command curl
            local temp_dir drawio_url deb_file; temp_dir="$(new_temp_dir)"; deb_file="${temp_dir}/drawio-amd64.deb"
            log "Resolving the latest official draw.io Desktop Linux package."
            drawio_url="$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 120 -H 'Accept: application/vnd.github+json' -- "${DRAWIO_RELEASE_API}" | sed -n 's/.*"browser_download_url": "\([^\"]*drawio-amd64-[^\"]*\.deb\)".*/\1/p' | head -n 1)"
            [[ -n "${drawio_url}" ]] || fail "Unable to locate the latest official draw.io AMD64 .deb."
            curl_download "${drawio_url}" "${deb_file}" "the official draw.io Desktop Linux package"
            require_downloaded_file "${deb_file}" "draw.io Desktop"; log "Installing draw.io Desktop."; sudo apt-get install -y -- "${deb_file}"
            ;;
        nextcloud)
            require_amd64 "Nextcloud Desktop AppImage"; require_command curl
            local temp_dir nextcloud_url appimage_path desktop_dir appimage_file; temp_dir="$(new_temp_dir)"
            nextcloud_url="$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 120 -- "${NEXTCLOUD_RELEASE_URL}" | sed -n 's/.*href="\(Nextcloud-[0-9][^\"]*-x86_64\.AppImage\)".*/\1/p' | sort -V | tail -n 1)"
            [[ -n "${nextcloud_url}" ]] || fail "Unable to locate the latest official Nextcloud x86_64 AppImage."
            appimage_path="${HOME}/.local/bin/nextcloud"; desktop_dir="${HOME}/.local/share/applications"; appimage_file="${temp_dir}/nextcloud.AppImage"
            mkdir -p "${HOME}/.local/bin" "${desktop_dir}"
            curl_download "${NEXTCLOUD_RELEASE_URL}${nextcloud_url}" "${appimage_file}" "the official Nextcloud Desktop Client AppImage"
            require_downloaded_file "${appimage_file}" "Nextcloud Desktop Client"; install -m 0755 "${appimage_file}" "${appimage_path}"
            cat > "${desktop_dir}/nextcloud.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Nextcloud Desktop Client
Comment=Synchronize files with a Nextcloud server
Exec=${appimage_path}
Icon=nextcloud
Terminal=false
Categories=Network;FileTransfer;
StartupNotify=true
EOF
            log "Nextcloud Desktop Client installed at ${appimage_path}."
            ;;
        chirp)
            require_amd64 "CHIRP"; require_command git
            install_apt_packages install python3-wxgtk4.0 python3-yattag pipx git
            if pipx list 2>/dev/null | grep -qE 'package chirp '; then log "Updating the existing pipx-managed CHIRP installation."; pipx uninstall chirp; fi
            log "Installing CHIRP-next from the official CHIRP Git repository."
            pipx install --system-site-packages "git+${CHIRP_GIT_URL}"
            log "CHIRP-next installed. Launch it with 'chirp' or from the desktop application menu."
            ;;
    esac
}

choose_packages() {
    local mode="${1}" title="${2}"
    local -a packages names recs reasons sources states
    local -a selected=() available_numbers=() recommended_numbers=() all_numbers=()
    local i choice
    if [[ "${mode}" == remove ]]; then packages=("${REMOVE_PACKAGES[@]}"); names=("${REMOVE_NAMES[@]}"); recs=("${REMOVE_RECS[@]}"); reasons=("${REMOVE_REASONS[@]}"); sources=("${REMOVE_SOURCES[@]}"); states=("${REMOVE_STATES[@]}")
    else packages=("${INSTALL_PACKAGES[@]}"); names=("${INSTALL_NAMES[@]}"); recs=("${INSTALL_RECS[@]}"); reasons=("${INSTALL_REASONS[@]}"); sources=("${INSTALL_SOURCES[@]}"); states=("${INSTALL_STATES[@]}"); fi
    [[ "${#packages[@]}" -gt 0 ]] || return 0
    printf '\n%s\n' "${title}"; printf '%s\n' "------------------------------------------------------------"
    for i in "${!packages[@]}"; do
        printf '  [%2d] %-20s [%s] %s\n' "$((i+1))" "${names[$i]}" "${recs[$i]}" "${states[$i]}"
        printf '       %s\n' "${reasons[$i]}"
        all_numbers+=("$((i+1))")
        [[ "${recs[$i]}" == RECOMMENDED ]] && recommended_numbers+=("$((i+1))")
    done
    printf '\nSelect: r=recommended, a=all, n=none, or numbers separated by spaces: '
    read -r choice
    case "${choice}" in
        r) selected=("${recommended_numbers[@]}") ;;
        a) selected=("${all_numbers[@]}") ;;
        n|'') selected=() ;;
        *) read -ra selected <<< "${choice}"; for i in "${selected[@]}"; do [[ "${i}" =~ ^[0-9]+$ ]] || fail "Invalid selection '${i}'."; (( i >= 1 && i <= ${#packages[@]} )) || fail "Selection '${i}' is out of range."; done ;;
    esac
    if [[ "${mode}" == remove ]]; then REMOVE_SELECTED=(); for i in "${selected[@]}"; do REMOVE_SELECTED+=("${packages[$((i-1))]}"); done
    else INSTALL_SELECTED=(); for i in "${selected[@]}"; do INSTALL_SELECTED+=("${packages[$((i-1))]}"); done; fi
}

validate_catalog
load_catalog
REMOVE_SELECTED=()
INSTALL_SELECTED=()
choose_packages remove "FieldKit — Remove applications"
choose_packages install "FieldKit — Install applications"

if [[ "${DRY_RUN}" == true ]]; then
    if [[ "${#REMOVE_SELECTED[@]}" -gt 0 ]]; then
        for package in "${REMOVE_SELECTED[@]}"; do log "DRY RUN: would remove ${package}."; done
    fi
    if [[ "${#INSTALL_SELECTED[@]}" -gt 0 ]]; then
        for package in "${INSTALL_SELECTED[@]}"; do
            if [[ "${package}" == "tailscale" ]]; then dry_run_external_package tailscale
            elif [[ "${package}" == "wifiman" || "${package}" == "drawio" || "${package}" == "nextcloud" || "${package}" == "chirp" ]]; then dry_run_external_package "${package}"
            else log "DRY RUN: would install ${package}."; fi
        done
    fi
    log "FieldKit dry run completed. No system changes were made."
    exit 0
fi

if [[ "${#REMOVE_SELECTED[@]}" -gt 0 ]]; then log "Removing selected packages."; install_apt_packages remove "${REMOVE_SELECTED[@]}"; fi

if [[ "${#INSTALL_SELECTED[@]}" -gt 0 ]]; then
    apt_packages=()
    external_packages=()
    for package in "${INSTALL_SELECTED[@]}"; do
        source=""
        for i in "${!INSTALL_PACKAGES[@]}"; do [[ "${INSTALL_PACKAGES[$i]}" == "${package}" ]] && source="${INSTALL_SOURCES[$i]}" && break; done
        if [[ "${source}" == apt ]]; then apt_packages+=("${package}"); else external_packages+=("${package}"); fi
    done
    [[ "${#apt_packages[@]}" -eq 0 ]] || install_apt_packages install "${apt_packages[@]}"
    for package in "${external_packages[@]}"; do
        [[ "${package}" == "tailscale" ]] && setup_tailscale_repository
        install_external_package "${package}"
    done
fi

log "FieldKit installer completed. Review ${LOG_FILE}."
