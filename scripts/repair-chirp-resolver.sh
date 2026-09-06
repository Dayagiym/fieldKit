#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALLER="${SCRIPT_DIR}/fieldkit-install.sh"

[[ -f "${INSTALLER}" ]] || { printf 'ERROR: %s not found.\n' "${INSTALLER}" >&2; exit 1; }

python3 - "${INSTALLER}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()

old = '''            if [[ -z "${chirp_release_dir}" ]]; then
                log "CHIRP archive index did not expose its directory listing; probing recent dated CHIRP-next wheel URLs directly."
                for offset in $(seq 0 60); do
                    candidate_date="$(date -d "-${offset} days" '+%Y%m%d')"
                    candidate_dir="next-${candidate_date}"
                    candidate_wheel="chirp-${candidate_date}-py3-none-any.whl"
                    candidate_url="${CHIRP_RELEASE_BASE_URL}${candidate_dir}/${candidate_wheel}"
                    if curl -fsSL --retry 2 --retry-delay 1 --connect-timeout 10 --max-time 30 -o /dev/null -- "${candidate_url}"; then
                        chirp_release_dir="${candidate_dir}"
                        chirp_url="${candidate_wheel}"
                        log "Found CHIRP-next build ${candidate_date}."
                        break
                    fi
                done
            fi
'''

new = '''            if [[ -z "${chirp_release_dir}" ]]; then
                log "CHIRP archive index did not expose its directory listing; probing recent dated CHIRP-next wheel URLs with an official-site referrer."
                for offset in $(seq 0 60); do
                    candidate_date="$(date -d "-${offset} days" '+%Y%m%d')"
                    candidate_dir="next-${candidate_date}"
                    candidate_wheel="chirp-${candidate_date}-py3-none-any.whl"
                    candidate_url="${CHIRP_RELEASE_BASE_URL}${candidate_dir}/${candidate_wheel}"
                    if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 30 -A 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131 Safari/537.36' -e 'https://chirpmyradio.com/projects/chirp/wiki/Download' -o /dev/null -- "${candidate_url}"; then
                        chirp_release_dir="${candidate_dir}"
                        chirp_url="${candidate_wheel}"
                        log "Found CHIRP-next build ${candidate_date}."
                        break
                    fi
                done
            fi
'''

if old not in text:
    raise SystemExit("ERROR: Expected CHIRP resolver block was not found; refusing to modify the installer.")

path.write_text(text.replace(old, new, 1))
PY

bash -n "${INSTALLER}"
printf 'CHIRP resolver repaired successfully.\n'
printf 'Run: bash -n %s\n' "${INSTALLER}"
printf 'Then: ./scripts/fieldkit-install-cinnamon.sh --dry-run\n'