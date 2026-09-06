#!/usr/bin/env bash
# Install a desktop launcher for a pipx-managed CHIRP installation.
set -Eeuo pipefail

readonly DESKTOP_DIR="${HOME}/.local/share/applications"
readonly DESKTOP_FILE="${DESKTOP_DIR}/chirp.desktop"
readonly CHIRP_BIN="${HOME}/.local/bin/chirp"

[[ -x "${CHIRP_BIN}" ]] || {
    printf 'ERROR: CHIRP was not found at %s. Install CHIRP with FieldKit first.\n' "${CHIRP_BIN}" >&2
    exit 1
}

mkdir -p "${DESKTOP_DIR}"

cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Type=Application
Name=CHIRP
Comment=Radio programming software
Exec=${CHIRP_BIN}
Terminal=false
Categories=Utility;HamRadio;
StartupNotify=true
EOF

chmod 0644 "${DESKTOP_FILE}"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "${DESKTOP_DIR}" >/dev/null 2>&1 || true
fi

printf 'CHIRP desktop launcher installed: %s\n' "${DESKTOP_FILE}"
printf 'CHIRP should now appear in the MATE/Cinnamon application menu.\n'
