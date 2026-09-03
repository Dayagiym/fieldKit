#!/usr/bin/env bash
#
# Mint FieldKit installer
#
# Interactive package selection for Linux Mint 22.3 MATE.
# Package recommendations live in config/packages.conf so the catalog can grow
# without turning this installer into a hard-coded package list.
#
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
mkdir -p "${LOG_DIR}"

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "${LOG_FILE}"; }
fail() { log "ERROR: $*"; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"; }

usage() {
    cat <<'EOF'
Usage: fieldkit-install.sh [--dry-run]

  --dry-run     Show package choices and planned changes without modifying the system.
  -h, --help    Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown option: $1" ;;
    esac
    shift
done

log "Starting ${SCRIPT_NAME} installer."
[[ "${EUID}" -eq 0 ]] && fail "Do not run this script as root. Run it as your normal user; sudo will be requested when needed."
require_command sudo
require_command lsb_release
require_command apt-get
require_command apt-cache
require_command dpkg-query
[[ -f "${CONFIG_FILE}" ]] || fail "Package catalog not found: ${CONFIG_FILE}"

if [[ "$(lsb_release -is)" != "Linuxmint" ]]; then
    fail "This installer is intended for Linux Mint. Detected: $(lsb_release -is)"
fi
mint_release="$(lsb_release -rs)"
[[ "${mint_release}" == "22.3" ]] || fail "This version targets Linux Mint 22.3. Detected: ${mint_release}"
if [[ "${XDG_CURRENT_DESKTOP:-}" != *MATE* && "${XDG_CURRENT_DESKTOP:-}" != *MATE:* ]]; then
    log "WARNING: MATE desktop was not detected from XDG_CURRENT_DESKTOP='${XDG_CURRENT_DESKTOP:-unset}'."
fi
log "Validated Linux Mint ${mint_release}."

is_installed() {
    local package="$1"
    [[ "$(dpkg-query -W -f='${Status}' "${package}" 2>/dev/null || true)" == "install ok installed" ]]
}

apt_package_available() {
    local package="$1"
    apt-cache show "${package}" >/dev/null 2>&1
}

setup_tailscale_repository() {
    if is_installed tailscale || apt_package_available tailscale; then return 0; fi
    if [[ "${DRY_RUN}" == true ]]; then
        log "DRY RUN: Tailscale external source detected; it will be available during a real run."
        return 0
    fi
    if ! command -v curl >/dev/null 2>&1; then
        log "curl is required to configure Tailscale; installing curl first."
        sudo apt-get install -y curl
    fi
    local ubuntu_codename="${UBUNTU_CODENAME:-}"
    if [[ -z "${ubuntu_codename}" && -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        ubuntu_codename="${UBUNTU_CODENAME:-}"
    fi
    [[ -n "${ubuntu_codename}" ]] || fail "Unable to determine the Ubuntu base codename required for the Tailscale repository."
    case "${ubuntu_codename}" in
        noble|jammy|focal|bionic|xenial) ;;
        *) fail "Unsupported Ubuntu base '${ubuntu_codename}' for the Tailscale repository." ;;
    esac
    log "Configuring the official Tailscale APT repository for Ubuntu ${ubuntu_codename}."
    sudo mkdir -p --mode=0755 /usr/share/keyrings
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${ubuntu_codename}.noarmor.gpg" | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${ubuntu_codename}.tailscale-keyring.list" | sudo tee /etc/apt/sources.list.d/tailscale.list >/dev/null
}

load_catalog() {
    REMOVE_PACKAGES=(); REMOVE_NAMES=(); REMOVE_RECS=(); REMOVE_REASONS=(); REMOVE_SOURCES=()
    INSTALL_PACKAGES=(); INSTALL_NAMES=(); INSTALL_RECS=(); INSTALL_REASONS=(); INSTALL_SOURCES=(); INSTALL_STATES=()
    while IFS='|' read -r action package name recommendation reason source; do
        [[ -z "${action}" || "${action}" == \#* ]] && continue
        case "${action}" in
            remove)
                if is_installed "${package}"; then
                    REMOVE_PACKAGES+=("${package}"); REMOVE_NAMES+=("${name}"); REMOVE_RECS+=("${recommendation}"); REMOVE_REASONS+=("${reason}"); REMOVE_SOURCES+=("${source}")
                fi
                ;;
            install)
                INSTALL_PACKAGES+=("${package}"); INSTALL_NAMES+=("${name}"); INSTALL_RECS+=("${recommendation}"); INSTALL_REASONS+=("${reason}"); INSTALL_SOURCES+=("${source}")
                if is_installed "${package}"; then INSTALL_STATES+=("INSTALLED")
                elif [[ "${source}" == external:* ]]; then INSTALL_STATES+=("EXTERNAL")
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
        ((line_number += 1))
        [[ -z "${line}" || "${line}" == \#* ]] && continue
        IFS='|' read -r action package name recommendation reason source extra <<< "${line}"
        [[ -z "${action}" || -z "${package}" || -z "${name}" || -z "${recommendation}" || -z "${reason}" || -z "${source}" || -n "${extra}" ]] && fail "Malformed package catalog entry at ${CONFIG_FILE}:${line_number}"
        case "${action}" in install|remove) ;; *) fail "Invalid action '${action}' at ${CONFIG_FILE}:${line_number}" ;; esac
        case "${source}" in apt|external:*) ;; *) fail "Invalid source '${source}' at ${CONFIG_FILE}:${line_number}" ;; esac
        [[ "${package}" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || fail "Invalid package name '${package}' at ${CONFIG_FILE}:${line_number}"
    done < "${CONFIG_FILE}"
}

contains_number() {
    local needle="$1"; shift; local value
    for value in "$@"; do [[ "${value}" == "${needle}" ]] && return 0; done
    return 1
}

dry_run_external_package() {
    local package="$1"
    case "${package}" in
        tailscale) log "DRY RUN: would configure the official Tailscale APT repository and install Tailscale." ;;
        wifiman) log "DRY RUN: would download and install the official Ubiquiti WiFiman Desktop AMD64 package." ;;
        drawio) log "DRY RUN: would resolve the latest official draw.io Desktop AMD64 package from GitHub and install it." ;;
        nextcloud) log "DRY RUN: would download the latest official Nextcloud Desktop x86_64 AppImage and install it for the current user." ;;
        chirp) log "DRY RUN: would install CHIRP dependencies, download the latest official CHIRP-next wheel, and install it with pipx." ;;
        *) fail "No external installer is defined for package '${package}'." ;;
    esac
}

install_external_package() {
    local package="$1"
    case "${package}" in
        tailscale)
            log "Installing Tailscale from its configured official APT repository."
            sudo apt-get install tailscale
            ;;
        wifiman)
            [[ "$(dpkg --print-architecture)" == "amd64" ]] || fail "WiFiman Desktop currently requires an amd64/x86_64 system."
            command -v curl >/dev/null 2>&1 || { log "curl is required to download WiFiman; installing curl first."; sudo apt-get install -y curl; }
            local temp_dir deb_file
            temp_dir="$(mktemp -d)"; deb_file="${temp_dir}/wifiman-desktop.deb"
            log "Downloading the official Ubiquiti WiFiman Desktop Linux package."
            curl -fL --retry 3 --retry-delay 2 "${WIFIMAN_DOWNLOAD_URL}" -o "${deb_file}"
            log "Installing WiFiman Desktop."
            sudo apt-get install "${deb_file}"
            rm -rf -- "${temp_dir}"
            ;;
        drawio)
            [[ "$(dpkg --print-architecture)" == "amd64" ]] || fail "draw.io Desktop currently requires an amd64/x86_64 system."
            command -v curl >/dev/null 2>&1 || { log "curl is required to download draw.io; installing curl first."; sudo apt-get install -y curl; }
            local temp_dir drawio_url deb_file
            temp_dir="$(mktemp -d)"; deb_file="${temp_dir}/drawio-amd64.deb"
            log "Resolving the latest official draw.io Desktop Linux package."
            drawio_url="$(curl -fsSL -H 'Accept: application/vnd.github+json' "${DRAWIO_RELEASE_API}" | sed -n 's/.*"browser_download_url": "\([^\"]*draw\.io-amd64-[^\"]*\.deb\)".*/\1/p' | head -n 1)"
            [[ -n "${drawio_url}" ]] || fail "Unable to locate the latest official draw.io AMD64 .deb."
            log "Downloading the official draw.io Desktop Linux package."
            curl -fL --retry 3 --retry-delay 2 "${drawio_url}" -o "${deb_file}"
            log "Installing draw.io Desktop."
            sudo apt-get install "${deb_file}"
            rm -rf -- "${temp_dir}"
            ;;
        nextcloud)
            [[ "$(dpkg --print-architecture)" == "amd64" ]] || fail "Nextcloud Desktop AppImage currently requires an amd64/x86_64 system."
            command -v curl >/dev/null 2>&1 || { log "curl is required to download Nextcloud Client; installing curl first."; sudo apt-get install -y curl; }
            local temp_dir nextcloud_url appimage_path desktop_dir
            temp_dir="$(mktemp -d)"
            nextcloud_url="$(curl -fsSL "${NEXTCLOUD_RELEASE_URL}" | sed -n 's/.*href="\(Nextcloud-[0-9][^\"]*-x86_64\.AppImage\)".*/\1/p' | sort -V | tail -n 1)"
            [[ -n "${nextcloud_url}" ]] || fail "Unable to locate the latest official Nextcloud x86_64 AppImage."
            appimage_path="${HOME}/.local/bin/nextcloud"
            desktop_dir="${HOME}/.local/share/applications"
            mkdir -p "${HOME}/.local/bin" "${desktop_dir}"
            log "Downloading the official Nextcloud Desktop Client AppImage: ${nextcloud_url}"
            curl -fL --retry 3 --retry-delay 2 "${NEXTCLOUD_RELEASE_URL}${nextcloud_url}" -o "${temp_dir}/nextcloud.AppImage"
            install -m 0755 "${temp_dir}/nextcloud.AppImage" "${appimage_path}"
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
            rm -rf -- "${temp_dir}"
            log "Nextcloud Desktop Client installed at ${appimage_path}."
            ;;
        chirp)
            [[ "$(dpkg --print-architecture)" == "amd64" ]] || fail "CHIRP currently requires an amd64/x86_64 system."
            command -v curl >/dev/null 2>&1 || { log "curl is required to download CHIRP; installing curl first."; sudo apt-get install -y curl; }
            command -v pipx >/dev/null 2>&1 || { log "pipx is required for CHIRP; installing it first."; sudo apt-get install -y pipx; }
            sudo apt-get install -y python3-wxgtk4.0 python3-yattag pipx
            local temp_dir chirp_release_dir chirp_url wheel_file
            temp_dir="$(mktemp -d)"
            chirp_release_dir="$(curl -fsSL "${CHIRP_RELEASE_BASE_URL}" | sed -n 's/.*href="\(next-[0-9][0-9]*\)\/".*/\1/p' | sort -V | tail -n 1)"
            [[ -n "${chirp_release_dir}" ]] || fail "Unable to locate the latest official CHIRP-next build."
            chirp_url="$(curl -fsSL "${CHIRP_RELEASE_BASE_URL}${chirp_release_dir}/" | sed -n 's/.*href="\(chirp-[0-9][0-9]*-py3-none-any\.whl\)".*/\1/p' | sort -V | tail -n 1)"
            [[ -n "${chirp_url}" ]] || fail "Unable to locate the latest official CHIRP Python wheel."
            wheel_file="${temp_dir}/${chirp_url}"
            log "Downloading the latest official CHIRP-next Python wheel: ${chirp_url}"
            curl -fL --retry 3 --retry-delay 2 "${CHIRP_RELEASE_BASE_URL}${chirp_release_dir}/${chirp_url}" -o "${wheel_file}"
            if pipx list 2>/dev/null | grep -qE 'package chirp '; then
                log "Removing the existing pipx-managed CHIRP installation before upgrade."
                pipx uninstall chirp
            fi
            log "Installing CHIRP-next for the current user."
            pipx install --system-site-packages "${wheel_file}"
            rm -rf -- "${temp_dir}"
            log "CHIRP-next installed. Launch it with 'chirp' or from the desktop application menu."
            ;;
        *) fail "No external installer is defined for package '${package}'." ;;
    esac
}

choose_packages() {
    local action="$1"; local -n packages="$2"; local -n names="$3"; local -n recommendations="$4"; local -n reasons="$5"; local -n sources="$6"; local -n states="$7"
    local -a selected=(); local prompt answer item
    if [[ "${#packages[@]}" -eq 0 ]]; then log "No matching ${action} candidates were found on this system."; printf '\n'; return 0; fi
    printf '\n'
    if [[ "${action}" == "remove" ]]; then printf '%s\n' "FieldKit — Applications detected for possible removal"; else printf '%s\n' "FieldKit — Field applications"; fi
    printf '%s\n\n' '------------------------------------------------------------'
    for item in "${!packages[@]}"; do
        if [[ "${action}" == "remove" ]]; then printf '  [%2d] %-20s %-12s %s\n' "$((item + 1))" "${names[item]}" "[${recommendations[item]}]" "${packages[item]}"
        else printf '  [%2d] %-20s %-12s %-11s %s\n' "$((item + 1))" "${names[item]}" "[${recommendations[item]}]" "${states[item]}" "${packages[item]}"; fi
        printf '       %s\n' "${reasons[item]}"
    done
    printf '\nEnter numbers separated by spaces/commas, or: r=recommended, a=all, n=none\n'
    [[ "${action}" == "remove" ]] && prompt='Remove' || prompt='Install'
    while true; do
        read -r -p "${prompt} selection: " answer; answer="${answer//,/ }"; selected=()
        case "${answer,,}" in
            n|none|'') ;;
            a|all)
                for item in "${!packages[@]}"; do
                    if [[ "${action}" == "remove" || "${states[item]}" == "AVAILABLE" || "${states[item]}" == "EXTERNAL" ]]; then selected+=("${item}"); fi
                done
                ;;
            r|recommended)
                for item in "${!packages[@]}"; do
                    if [[ "${action}" == "remove" ]]; then [[ "${recommendations[item]}" == "REMOVE" ]] && selected+=("${item}")
                    elif [[ "${recommendations[item]}" == "RECOMMENDED" && ( "${states[item]}" == "AVAILABLE" || "${states[item]}" == "EXTERNAL" ) ]]; then selected+=("${item}"); fi
                done
                ;;
            *)
                local valid=true
                for item in ${answer}; do
                    [[ "${item}" =~ ^[0-9]+$ ]] || { valid=false; break; }
                    item=$((item - 1)); (( item >= 0 && item < ${#packages[@]} )) || { valid=false; break; }
                    if [[ "${action}" == "install" && "${states[item]}" != "AVAILABLE" && "${states[item]}" != "EXTERNAL" ]]; then printf 'Package %s is not available for installation (%s).\n' "${names[item]}" "${states[item]}"; valid=false; break; fi
                    contains_number "${item}" "${selected[@]}" || selected+=("${item}")
                done
                ${valid} || { printf 'Invalid selection. Please try again.\n'; continue; }
                ;;
        esac
        break
    done
    [[ "${#selected[@]}" -eq 0 ]] && return 0
    printf '\nSelected packages:\n'
    for item in "${selected[@]}"; do
        if [[ "${action}" == "install" ]]; then printf '  - %s (%s) [%s]\n' "${names[item]}" "${packages[item]}" "${states[item]}"; else printf '  - %s (%s)\n' "${names[item]}" "${packages[item]}"; fi
    done
    printf '\n'
    if [[ "${DRY_RUN}" == true ]]; then
        if [[ "${action}" == "install" ]]; then
            for item in "${selected[@]}"; do
                if [[ "${sources[item]}" == external:* ]]; then
                    dry_run_external_package "${packages[item]}"
                else
                    log "DRY RUN: would install APT package ${packages[item]}."
                fi
            done
        else
            for item in "${selected[@]}"; do
                log "DRY RUN: would remove ${packages[item]} (purge)."
            done
        fi
        printf 'DRY RUN: no packages will be changed.\n'
        return 0
    fi
    read -r -p "Proceed with this ${action} operation? [y/N] " answer
    [[ "${answer}" =~ ^[Yy]$ ]] || { log "${action^} operation cancelled by user."; return 0; }
    local -a selected_packages=()
    for item in "${selected[@]}"; do selected_packages+=("${packages[item]}"); done
    if [[ "${action}" == "remove" ]]; then
        log "Previewing removal of selected packages: ${selected_packages[*]}"
        sudo apt-get -s remove --purge "${selected_packages[@]}"
        read -r -p "Removal preview completed. Execute the removal? [y/N] " answer
        [[ "${answer}" =~ ^[Yy]$ ]] || { log "Removal cancelled after preview."; return 0; }
        log "Removing selected packages: ${selected_packages[*]}"
        sudo apt-get remove --purge "${selected_packages[@]}"
    else
        local index package source
        for index in "${selected[@]}"; do
            package="${packages[index]}"; source="${sources[index]}"
            if [[ "${source}" == external:* ]]; then install_external_package "${package}"; else log "Installing selected APT package: ${package}"; sudo apt-get install "${package}"; fi
        done
    fi
}

validate_catalog
load_catalog
for item in "${!INSTALL_PACKAGES[@]}"; do
    if [[ "${INSTALL_SOURCES[item]}" == "external:tailscale" ]]; then setup_tailscale_repository; break; fi
done

choose_packages remove REMOVE_PACKAGES REMOVE_NAMES REMOVE_RECS REMOVE_REASONS REMOVE_SOURCES REMOVE_STATES
choose_packages install INSTALL_PACKAGES INSTALL_NAMES INSTALL_RECS INSTALL_REASONS INSTALL_SOURCES INSTALL_STATES

log "FieldKit installer completed. Review ${LOG_FILE}."
