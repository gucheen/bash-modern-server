#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/lib/common.sh"

KEEP_CONFIG=0
[[ "${1:-}" == "--keep-config" ]] && KEEP_CONFIG=1
[[ $# -le 1 ]] || die "usage: ./uninstall.sh [--keep-config]"

validate_paths
backup="$(create_backup)"
info "Backup saved to ${backup}"

if [[ -f "${BASHRC_FILE}" ]]; then
    tmp="${BASHRC_FILE}.tmp.$$"
    strip_managed_block "${BASHRC_FILE}" "${tmp}"
    mv "${tmp}" "${BASHRC_FILE}"
fi
if [[ ${KEEP_CONFIG} -eq 0 && -d "${CONFIG_DIR}" ]]; then
    rm -rf "${CONFIG_DIR}"
fi
info "Uninstall complete"

