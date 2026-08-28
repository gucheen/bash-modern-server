#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

export HOME="${TEST_ROOT}/home"
export BASH_MODERN_HOME="${HOME}/.config/bash-modern"
export BASH_MODERN_BACKUP_ROOT="${HOME}/.local/state/bash-modern/backups"
export BASH_MODERN_BASHRC="${HOME}/.bashrc"
mkdir -p "${HOME}"
printf '# original\nalias mine=true\n' >"${BASH_MODERN_BASHRC}"

"${ROOT_DIR}/install.sh" --skip-downloads >/dev/null
grep -Fq '# original' "${BASH_MODERN_BASHRC}"
[[ "$(grep -Fc '# >>> bash-modern-server >>>' "${BASH_MODERN_BASHRC}")" -eq 1 ]]
[[ -x "${BASH_MODERN_HOME}/bin/bash-modern" ]]
! grep -Fq 'export BASH_MODERN_LOADED' "${BASH_MODERN_HOME}/bashrc"
grep -Fq 'format = "$username$hostname$directory$git_branch$git_status$cmd_duration$status$character"' "${BASH_MODERN_HOME}/starship.toml"
grep -Fq "success_symbol = '[\\\$](green) '" "${BASH_MODERN_HOME}/starship.toml"
! grep -Fq 'PROMPT_COMMAND="history -a; history -n' "${BASH_MODERN_HOME}/bashrc.d/00-history.sh"
[[ ! -e "${BASH_MODERN_HOME}/bashrc.d/90-blesh.sh" ]]
[[ ! -d "${BASH_MODERN_HOME}/vendor/blesh" ]]
grep -Fq 'backward-kill-word' "${BASH_MODERN_HOME}/bashrc.d/10-shell-options.sh"
[[ -f "${BASH_MODERN_HOME}/bashrc.d/99-zoxide.sh" ]]
! grep -Fq 'zoxide init bash' "${BASH_MODERN_HOME}/bashrc.d/30-integrations.sh"
grep -Fq 'zoxide}" init bash' "${BASH_MODERN_HOME}/bashrc.d/99-zoxide.sh"

mkdir -p "${BASH_MODERN_HOME}/vendor/blesh"
touch "${BASH_MODERN_HOME}/vendor/blesh/ble.sh"
printf '#!/bin/sh\nexit 0\n' >"${BASH_MODERN_HOME}/bin/starship"
printf '#!/bin/sh\nexit 0\n' >"${BASH_MODERN_HOME}/bin/zoxide"
chmod +x "${BASH_MODERN_HOME}/bin/starship" "${BASH_MODERN_HOME}/bin/zoxide"
mkdir -p "${BASH_MODERN_HOME}/share/man/man1"
touch "${BASH_MODERN_HOME}/share/man/man1/zoxide.1"
"${ROOT_DIR}/install.sh" --skip-downloads >/dev/null
[[ "$(grep -Fc '# >>> bash-modern-server >>>' "${BASH_MODERN_BASHRC}")" -eq 1 ]]
[[ ! -d "${BASH_MODERN_HOME}/vendor/blesh" ]]
[[ -x "${BASH_MODERN_HOME}/bin/starship" ]]
[[ -x "${BASH_MODERN_HOME}/bin/zoxide" ]]
[[ -f "${BASH_MODERN_HOME}/share/man/man1/zoxide.1" ]]
"${BASH_MODERN_HOME}/bin/bash-modern" doctor >/dev/null

backup="$("${BASH_MODERN_HOME}/bin/bash-modern" backup)"
printf '# changed\n' >"${BASH_MODERN_BASHRC}"
"${BASH_MODERN_HOME}/bin/bash-modern" rollback "${backup}" >/dev/null
grep -Fq '# original' "${BASH_MODERN_BASHRC}"

"${ROOT_DIR}/uninstall.sh" >/dev/null
grep -Fq '# original' "${BASH_MODERN_BASHRC}"
! grep -Fq '# >>> bash-modern-server >>>' "${BASH_MODERN_BASHRC}"
[[ ! -d "${BASH_MODERN_HOME}" ]]

printf 'all tests passed\n'
