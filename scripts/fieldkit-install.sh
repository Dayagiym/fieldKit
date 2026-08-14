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

DRY_RUN=false

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

usage() {
    cat <<'EOF'
Usage: fieldkit-install.sh [--dry-run]

  --dry-run    Show the package choices without changing the system.
  -h, --help   Show this help.
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
if [[ "${mint_release}" != "22.3" ]]; then
    fail "This version targets Linux Mint 22.3. Detected: ${mint_release}"
fi

if [[ "${XDG_CURRENT_DESKTOP:-}" != *MATE* && "${XDG_CURRENT_DESKTOP:-}" != *MATE:* ]]; then
    log "WARNING: MATE desktop was not detected from XDG_CURRENT_DESKTOP='${XDG_CURRENT_DESKTOP:-unset}'."
fi

log "Validated Linux Mint ${mint_release}."

is_installed() {
    local package="$1"
    [[ "$(dpkg-query -W -f='${Status}' "${package}" 2>/dev/null || true)" == "install ok installed" ]]
}

is_available() {
    local package="$1"
    apt-cache show "${package}" >/dev/null 2>&1
}

validate_catalog() {
    local line_number=0
    local line action package name recommendation reason extra

    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_number += 1))
        [[ -z "${line}" || "${line}" == \#* ]] && continue

        IFS='|' read -r action package name recommendation reason extra <<< "${line}"
        [[ -z "${action}" || -z "${package}" || -z "${name}" || -z "${recommendation}" || -z "${reason}" || -n "${extra}" ]] && \
            fail "Malformed package catalog entry at ${CONFIG_FILE}:${line_number}"

        case "${action}" in
            install|remove) ;;
            *) fail "Invalid action '${action}' at ${CONFIG_FILE}:${line_number}" ;;
        esac

        [[ "${package}" =~ ^[a-z0-9][a-z0-9+.-]*$ ]] || \
            fail "Invalid package name '${package}' at ${CONFIG_FILE}:${line_number}"
    done < "${CONFIG_FILE}"
}

load_catalog() {
    REMOVE_PACKAGES=()
    REMOVE_NAMES=()
    REMOVE_RECS=()
    REMOVE_REASONS=()

    INSTALL_PACKAGES=()
    INSTALL_NAMES=()
    INSTALL_RECS=()
    INSTALL_REASONS=()

    while IFS='|' read -r action package name recommendation reason; do
        [[ -z "${action}" || "${action}" == \#* ]] && continue

        case "${action}" in
            remove)
                if is_installed "${package}"; then
                    REMOVE_PACKAGES+=("${package}")
                    REMOVE_NAMES+=("${name}")
                    REMOVE_RECS+=("${recommendation}")
                    REMOVE_REASONS+=("${reason}")
                fi
                ;;
            install)
                if ! is_installed "${package}" && is_available "${package}"; then
                    INSTALL_PACKAGES+=("${package}")
                    INSTALL_NAMES+=("${name}")
                    INSTALL_RECS+=("${recommendation}")
                    INSTALL_REASONS+=("${reason}")
                fi
                ;;
            *)
                fail "Invalid action '${action}' in ${CONFIG_FILE}"
                ;;
        esac
    done < "${CONFIG_FILE}"
}

contains_number() {
    local needle="$1"
    shift
    local value
    for value in "$@"; do
        [[ "${value}" == "${needle}" ]] && return 0
    done
    return 1
}

choose_packages() {
    local action="$1"
    local -n packages="$2"
    local -n names="$3"
    local -n recommendations="$4"
    local -n reasons="$5"
    local -a selected=()
    local prompt answer item

    if [[ "${#packages[@]}" -eq 0 ]]; then
        log "No matching ${action} candidates were found on this system."
        printf '\n'
        return 0
    fi

    printf '\n'
    if [[ "${action}" == "remove" ]]; then
        printf '%s\n' "FieldKit — Applications detected for possible removal"
    else
        printf '%s\n' "FieldKit — Recommended field applications"
    fi
    printf '%s\n\n' '------------------------------------------------------------'

    for item in "${!packages[@]}"; do
        printf '  [%2d] %-20s %-12s %s\n' \
            "$((item + 1))" "${names[item]}" "[${recommendations[item]}]" "${packages[item]}"
        printf '       %s\n' "${reasons[item]}"
    done

    printf '\n'
    printf 'Enter numbers separated by spaces/commas, or: r=recommended, a=all, n=none\n'
    if [[ "${action}" == "remove" ]]; then
        prompt='Remove'
    else
        prompt='Install'
    fi

    while true; do
        read -r -p "${prompt} selection: " answer
        answer="${answer//,/ }"
        selected=()

        case "${answer,,}" in
            n|none|'')
                ;;
            a|all)
                for item in "${!packages[@]}"; do
                    selected+=("${item}")
                done
                ;;
            r|recommended)
                for item in "${!packages[@]}"; do
                    [[ "${recommendations[item]}" == "RECOMMENDED" || "${recommendations[item]}" == "REMOVE" ]] && selected+=("${item}")
                done
                ;;
            *)
                local valid=true
                for item in ${answer}; do
                    [[ "${item}" =~ ^[0-9]+$ ]] || { valid=false; break; }
                    item=$((item - 1))
                    (( item >= 0 && item < ${#packages[@]} )) || { valid=false; break; }
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
        printf '  - %s (%s)\n' "${names[item]}" "${packages[item]}"
    done

    printf '\n'
    if [[ "${DRY_RUN}" == true ]]; then
        printf 'DRY RUN: no packages will be changed.\n'
        return 0
    fi

    read -r -p "Proceed with this ${action} operation? [y/N] " answer
    [[ "${answer}" =~ ^[Yy]$ ]] || { log "${action^} operation cancelled by user."; return 0; }

    local -a selected_packages=()
    for item in "${selected[@]}"; do
        selected_packages+=("${packages[item]}")
    done

    if [[ "${action}" == "remove" ]]; then
        log "Removing selected packages: ${selected_packages[*]}"
        sudo apt-get remove --purge "${selected_packages[@]}"
    else
        log "Installing selected packages: ${selected_packages[*]}"
        sudo apt-get install "${selected_packages[@]}"
    fi
}

validate_catalog
load_catalog

printf '\n%s\n' "=== ${SCRIPT_NAME} ==="
printf 'Validated target: Linux Mint %s MATE\n' "${mint_release}"
[[ "${DRY_RUN}" == true ]] && printf '%s\n' 'Mode: DRY RUN'
printf '\n'

choose_packages remove REMOVE_PACKAGES REMOVE_NAMES REMOVE_RECS REMOVE_REASONS

if [[ "${#INSTALL_PACKAGES[@]}" -gt 0 && "${DRY_RUN}" == false ]]; then
    printf '\nRefreshing APT package information before installation choices...\n'
    sudo apt-get update
    load_catalog
fi

choose_packages install INSTALL_PACKAGES INSTALL_NAMES INSTALL_RECS INSTALL_REASONS

log "FieldKit installer completed."
log "Review ${LOG_FILE} for the operation history."
