#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PROJECT_NAME="bash-modern-server"
CONFIG_DIR="${BASH_MODERN_HOME:-${HOME}/.config/bash-modern}"
BACKUP_ROOT="${BASH_MODERN_BACKUP_ROOT:-${HOME}/.local/state/bash-modern/backups}"
BASHRC_FILE="${BASH_MODERN_BASHRC:-${HOME}/.bashrc}"
BEGIN_MARKER="# >>> bash-modern-server >>>"
END_MARKER="# <<< bash-modern-server <<<"

info() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

validate_paths() {
    [[ -n "${HOME:-}" && "${HOME}" != "/" ]] || die "HOME is unsafe or empty"
    [[ -n "${CONFIG_DIR}" && "${CONFIG_DIR}" != "/" && "${CONFIG_DIR}" != "${HOME}" ]] || die "unsafe config path: ${CONFIG_DIR}"
    [[ -n "${BACKUP_ROOT}" && "${BACKUP_ROOT}" != "/" && "${BACKUP_ROOT}" != "${HOME}" ]] || die "unsafe backup path: ${BACKUP_ROOT}"
}

strip_managed_block() {
    local input=$1 output=$2
    awk -v begin="${BEGIN_MARKER}" -v end="${END_MARKER}" '
        $0 == begin { managed=1; next }
        $0 == end { managed=0; next }
        !managed { print }
    ' "${input}" >"${output}"
}

create_backup() {
    validate_paths
    local stamp backup
    stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
    backup="${BACKUP_ROOT}/${stamp}"
    mkdir -p "${backup}"

    if [[ -f "${BASHRC_FILE}" ]]; then
        cp -p "${BASHRC_FILE}" "${backup}/bashrc"
        printf '1\n' >"${backup}/bashrc.present"
    else
        printf '0\n' >"${backup}/bashrc.present"
    fi
    if [[ -d "${CONFIG_DIR}" ]]; then
        cp -a "${CONFIG_DIR}" "${backup}/config"
        printf '1\n' >"${backup}/config.present"
    else
        printf '0\n' >"${backup}/config.present"
    fi
    printf '%s\n' "${CONFIG_DIR}" >"${backup}/config.path"
    printf '%s\n' "${BASHRC_FILE}" >"${backup}/bashrc.path"
    printf '%s\n' "${backup}"
}

latest_backup() {
    [[ -d "${BACKUP_ROOT}" ]] || return 1
    find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -print | LC_ALL=C sort | tail -n 1
}

