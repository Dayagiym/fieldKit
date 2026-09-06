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

cinnamon_detected=false
case "${XDG_CURRENT_DESKTOP:-}:${XDG_SESSION_DESKTOP:-}:${DESKTOP_SESSION:-}" in
    *Cinnamon*|*cinnamon*|*X-Cinnamon*) cinnamon_detected=true ;;
esac

# SSH and other non-graphical sessions may not inherit desktop environment
# variables. In that case, confirm that a Cinnamon session is actually running.
if [[ "${cinnamon_detected}" != true ]] && pgrep -x cinnamon >/dev/null 2>&1; then
    cinnamon_detected=true
fi

if [[ "${cinnamon_detected}" != true ]]; then
    printf 'FieldKit Cinnamon: WARNING: Cinnamon was not detected from the current session.\n' >&2
    printf 'XDG_CURRENT_DESKTOP=%q XDG_SESSION_DESKTOP=%q DESKTOP_SESSION=%q\n' \
        "${XDG_CURRENT_DESKTOP:-unset}" "${XDG_SESSION_DESKTOP:-unset}" "${DESKTOP_SESSION:-unset}" >&2
    printf 'Continue anyway? [y/N] '
    read -r answer
    [[ "${answer}" =~ ^[Yy]$ ]] || exit 1
fi

export FIELDKIT_FLAVOR="Cinnamon"
exec "${INSTALLER}" "$@"
