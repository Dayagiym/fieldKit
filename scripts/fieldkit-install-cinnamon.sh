#!/usr/bin/env bash
# Mint FieldKit — Cinnamon flavor launcher
# Uses the common FieldKit installer with Linux Mint Cinnamon validation.
set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALLER="${SCRIPT_DIR}/fieldkit-install.sh"

fail() { printf 'FieldKit Cinnamon: ERROR: %s\n' "$*" >&2; exit 1; }

[[ -f "${INSTALLER}" ]] || fail "Common FieldKit installer not found: ${INSTALLER}"
command -v lsb_release >/dev/null 2>&1 || fail "lsb_release is required."
[[ "$(lsb_release -is)" == "Linuxmint" ]] || fail "This flavor is intended for Linux Mint. Detected: $(lsb_release -is)"
[[ "$(lsb_release -rs)" == "22.3" ]] || fail "This flavor targets Linux Mint 22.3. Detected: $(lsb_release -rs)"

case "${XDG_CURRENT_DESKTOP:-}" in
    *Cinnamon*|X-Cinnamon|X-Cinnamon:*) ;;
    *)
        printf 'FieldKit Cinnamon: WARNING: Cinnamon was not detected from XDG_CURRENT_DESKTOP=%q.\n' "${XDG_CURRENT_DESKTOP:-unset}" >&2
        printf 'Continue anyway? [y/N] '
        read -r answer
        [[ "${answer}" =~ ^[Yy]$ ]] || exit 1
        ;;
esac

export FIELDKIT_FLAVOR="Cinnamon"
exec "${INSTALLER}" "$@"
