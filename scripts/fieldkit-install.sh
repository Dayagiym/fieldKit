#!/usr/bin/env bash
# Mint FieldKit installer
# Interactive package selection for Linux Mint 22.3 MATE.
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
if [[ "${XDG_CURRENT_DESKTOP:-}" != *MATE* && "${XDG_CURRENT_DESKTOP:-}" != *MATE:* ]]; then log "WARNING: MATE desktop was not detected from XDG_CURRENT_DESKTOP='${XDG_CURRENT_DESKTOP:-unset}'."; fi
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
        wifiman) log "DRY RUN: WiFiman Desktop is skipped on Linux Mint 22.3 because the stable Ubiquiti 1.1.3 package requires libwebkit2gtk-4.0-37, which Ubuntu 24.04 does not provide." ;;
        drawio) log "DRY RUN: would resolve the latest official draw.io Desktop AMD64 package from GitHub and install it." ;;
        nextcloud) log "DRY RUN: would download the latest official Nextcloud Desktop x86_64 AppImage and install it for the current user." ;;
        chirp) log "DRY RUN: would install CHIRP dependencies, locate the latest official CHIRP-next wheel, and install it with pipx." ;;
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

chirp_wheel_for_date() {
    local candidate_date="$1" candidate_url="${CHIRP_RELEASE_BASE_URL}next-${candidate_date}/chirp-${candidate_date}-py3-none-any.whl" http_code
    http_code="$(curl -sS -L -o /dev/null -w '%{http_code}' --retry 1 --connect-timeout 10 --max-time 20 -A 'Mozilla/5.0' -H 'Range: bytes=0-0' -- "${candidate_url}" 2>/dev/null || true)"
    [[ "${http_code}" == "200" || "${http_code}" == "206" || "${http_code}" == "301" || "${http_code}" == "302" ]]
}

install_external_package() {
    local package="$1"
    case "${package}" in
        tailscale) log "Installing Tailscale from its configured official APT repository."; install_apt_packages install tailscale ;;
        wifiman)
            if [[ "$(ubuntu_codename)" == "noble" ]]; then
                log "WARNING: Skipping WiFiman Desktop on Linux Mint 22.3. Ubiquiti's stable Linux package 1.1.3 requires libwebkit2gtk-4.0-37, which is unavailable on Ubuntu 24.04. A newer Ubiquiti Linux build exists in Early Access, but FieldKit will not install an unreleased vendor package automatically."
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
            require_amd64 "CHIRP"; require_command curl
            install_apt_packages install python3-wxgtk4.0 python3-yattag pipx
            local temp_dir chirp_release_dir chirp_url wheel_file chirp_index candidate_date offset
            temp_dir="$(new_temp_dir)"
            chirp_release_dir="$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 120 -A 'Mozilla/5.0' -- "${CHIRP_RELEASE_BASE_URL}" 2>/dev/null | grep -oE 'next-[0-9]{8}/' | sed 's:/$::' | sort -V | tail -n 1 || true)"
            if [[ -n "${chirp_release_dir}" ]]; then
                chirp_url="$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 --max-time 120 -A 'Mozilla/5.0' -- "${CHIRP_RELEASE_BASE_URL}${chirp_release_dir}/" 2>/dev/null | grep -oE 'chirp-[0-9]{8}-py3-none-any\.whl' | sort -V | tail -n 1 || true)"
            fi
            if [[ -z "${chirp_url}" ]]; then
                log "CHIRP archive index did not expose its wheel listing; probing direct official dated wheel URLs."
                for offset in $(seq 0 21); do
                    candidate_date="$(date -d "-${offset} days" '+%Y%m%d')"
                    if chirp_wheel_for_date "${candidate_date}"; then
                        chirp_release_dir="next-${candidate_date}"
                        chirp_url="chirp-${candidate_date}-py3-none-any.whl"
                        break
                    fi
                done
            fi
            [[ -n "${chirp_release_dir:-}" && -n "${chirp_url:-}" ]] || fail "Unable to locate the latest official CHIRP-next build."
            wheel_file="${temp_dir}/${chirp_url}"
            curl_download "${CHIRP_RELEASE_BASE_URL}${chirp_release_dir}/${chirp_url}" "${wheel_file}" "the latest official CHIRP-next Python wheel"
            require_downloaded_file "${wheel_file}" "CHIRP-next"
            if pipx list 2>/dev/null | grep -qE 'package chirp '; then log "Updating the existing pipx-managed CHIRP installation."; pipx uninstall chirp; fi
            log "Installing CHIRP-next for the current user."; pipx install --system-site-packages "${wheel_file}"; log "CHIRP-next installed. Launch it with 'chirp' or from the desktop application menu."
            ;;
        *) fail "No external installer is defined for package '${package}'." ;;
    esac
}

choose_packages() {
    local action="$1"; local -n packages="$2"; local -n names="$3"; local -n recommendations="$4"; local -n reasons="$5"; local -n sources="$6"; local -n states="$7"
    local -a selected=(); local prompt answer item
    if [[ "${#packages[@]}" -eq 0 ]]; then log "No matching ${action} candidates were found on this system."; printf '\n'; return 0; fi
    printf '\n'; [[ "${action}" == remove ]] && printf '%s\n' "FieldKit — Applications detected for possible removal" || printf '%s\n' "FieldKit — Field applications"; printf '%s\n\n' '------------------------------------------------------------'
    for item in "${!packages[@]}"; do
        if [[ "${action}" == remove ]]; then printf '  [%2d] %-20s %-12s %s\n' "$((item + 1))" "${names[item]}" "[${recommendations[item]}]" "${packages[item]}"; else printf '  [%2d] %-20s %-12s %-11s %s\n' "$((item + 1))" "${names[item]}" "[${recommendations[item]}]" "${states[item]}" "${packages[item]}"; fi
        printf '       %s\n' "${reasons[item]}"
    done
    printf '\nEnter numbers separated by spaces/commas, or: r=recommended, a=all, n=none\n'; [[ "${action}" == remove ]] && prompt=Remove || prompt=Install
    while true; do
        read -r -p "${prompt} selection: " answer; answer="${answer//,/ }"; selected=()
        case "${answer,,}" in
            n|none|'') ;;
            a|all) for item in "${!packages[@]}"; do if [[ "${action}" == remove || "${states[item]}" == AVAILABLE || "${states[item]}" == EXTERNAL ]]; then selected+=("${item}"); fi; done ;;
            r|recommended) for item in "${!packages[@]}"; do if [[ "${action}" == remove ]]; then [[ "${recommendations[item]}" == REMOVE ]] && selected+=("${item}"); elif [[ "${recommendations[item]}" == RECOMMENDED && ( "${states[item]}" == AVAILABLE || "${states[item]}" == EXTERNAL ) ]]; then selected+=("${item}"); fi; done ;;
            *)
                local valid=true
                for item in ${answer}; do [[ "${item}" =~ ^[0-9]+$ ]] || { valid=false; break; }; item=$((item - 1)); (( item >= 0 && item < ${#packages[@]} )) || { valid=false; break; }; if [[ "${action}" == install && "${states[item]}" != AVAILABLE && "${states[item]}" != EXTERNAL ]]; then printf 'Package %s is not available for installation (%s).\n' "${names[item]}" "${states[item]}"; valid=false; break; fi; contains_number "${item}" "${selected[@]}" || selected+=("${item}"); done
                ${valid} || { printf 'Invalid selection. Please try again.\n'; continue; } ;;
        esac; break
    done
    [[ "${#selected[@]}" -eq 0 ]] && return 0
    printf '\nSelected packages:\n'; for item in "${selected[@]}"; do if [[ "${action}" == install ]]; then printf '  - %s (%s) [%s]\n' "${names[item]}" "${packages[item]}" "${states[item]}"; else printf '  - %s (%s)\n' "${names[item]}" "${packages[item]}"; fi; done; printf '\n'
    if [[ "${DRY_RUN}" == true ]]; then
        if [[ "${action}" == install ]]; then for item in "${selected[@]}"; do if [[ "${sources[item]}" == external:* ]]; then dry_run_external_package "${packages[item]}"; else log "DRY RUN: would install APT package ${packages[item]}."; fi; done; else for item in "${selected[@]}"; do log "DRY RUN: would remove ${packages[item]} (purge)."; done; fi
        printf 'DRY RUN: no packages will be changed.\n'; return 0
    fi
    read -r -p "Proceed with this ${action} operation? [y/N] " answer; [[ "${answer}" =~ ^[Yy]$ ]] || { log "${action^} operation cancelled by user."; return 0; }
    local -a selected_packages=(); for item in "${selected[@]}"; do selected_packages+=("${packages[item]}"); done
    if [[ "${action}" == remove ]]; then
        log "Previewing removal of selected packages: ${selected_packages[*]}"; sudo apt-get -s remove --purge -- "${selected_packages[@]}"; read -r -p "Removal preview completed. Execute the removal? [y/N] " answer; [[ "${answer}" =~ ^[Yy]$ ]] || { log "Removal cancelled after preview."; return 0; }; log "Removing selected packages: ${selected_packages[*]}"; install_apt_packages remove "${selected_packages[@]}"
    else
        local index package source
        for index in "${selected[@]}"; do
            package="${packages[index]}"; source="${sources[index]}"
            if [[ "${source}" == external:* ]]; then
                if ! install_external_package "${package}"; then log "ERROR: External package '${package}' failed to install. Continuing with remaining FieldKit selections."; fi
            else
                log "Installing selected APT package: ${package}"; install_apt_packages install "${package}"
            fi
        done
    fi
}

validate_catalog
load_catalog
for item in "${!INSTALL_PACKAGES[@]}"; do if [[ "${INSTALL_SOURCES[item]}" == external:tailscale ]]; then setup_tailscale_repository; break; fi; done
choose_packages remove REMOVE_PACKAGES REMOVE_NAMES REMOVE_RECS REMOVE_REASONS REMOVE_SOURCES REMOVE_STATES
choose_packages install INSTALL_PACKAGES INSTALL_NAMES INSTALL_RECS INSTALL_REASONS INSTALL_SOURCES INSTALL_STATES
log "FieldKit installer completed. Review ${LOG_FILE}."
