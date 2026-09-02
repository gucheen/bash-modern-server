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
grep -Fq -- '--install-deps' <("${ROOT_DIR}/install.sh" --help)
grep -Fq 'install-build-deps' <("${BASH_MODERN_HOME}/bin/bash-modern" --help)
! grep -Fq 'export BASH_MODERN_LOADED' "${BASH_MODERN_HOME}/bashrc"
grep -Fq 'format = "$username$hostname$directory$cmd_duration$status$character"' "${BASH_MODERN_HOME}/starship.toml"
grep -Fq 'format = "$username$hostname$directory$git_branch$git_status$cmd_duration$status$character"' "${BASH_MODERN_HOME}/starship-git.toml"
grep -Fq "success_symbol = '[\\\$](green) '" "${BASH_MODERN_HOME}/starship.toml"
! grep -Fq 'PROMPT_COMMAND="history -a; history -n' "${BASH_MODERN_HOME}/bashrc.d/00-history.sh"
[[ ! -e "${BASH_MODERN_HOME}/bashrc.d/90-blesh.sh" ]]
[[ ! -d "${BASH_MODERN_HOME}/vendor/blesh" ]]
grep -Fq 'backward-kill-word' "${BASH_MODERN_HOME}/bashrc.d/10-shell-options.sh"
[[ -f "${BASH_MODERN_HOME}/bashrc.d/99-zoxide.sh" ]]
[[ -f "${BASH_MODERN_HOME}/bashrc.d/40-abbreviations.sh" ]]
[[ -f "${BASH_MODERN_HOME}/bashrc.d/45-command-library.sh" ]]
[[ -f "${BASH_MODERN_HOME}/commands.d/20-common.sh" ]]
[[ -f "${BASH_MODERN_HOME}/commands.d/30-abbreviations.sh" ]]
[[ -f "${BASH_MODERN_HOME}/bashrc.d/35-native-prompt.sh" ]]
[[ ! -f "${BASH_MODERN_HOME}/user/starship.enabled" ]]
[[ ! -f "${BASH_MODERN_HOME}/user/git-status.enabled" ]]
[[ ! -x "${BASH_MODERN_HOME}/bin/starship" ]]
! grep -Fq 'zoxide init bash' "${BASH_MODERN_HOME}/bashrc.d/30-integrations.sh"
grep -Fq 'zoxide}" init bash' "${BASH_MODERN_HOME}/bashrc.d/99-zoxide.sh"
grep -Fq 'bash-autosuggestions/bash-autosuggestions.bash' "${BASH_MODERN_HOME}/bashrc.d/30-integrations.sh"

source "${BASH_MODERN_HOME}/bashrc.d/40-abbreviations.sh"
abbr --add gs git status
[[ "$(abbr --list)" == gs ]]
[[ "$(abbr --show gs)" == "abbr --add gs git\\ status" ]]
READLINE_LINE='sudo gs --short'
READLINE_POINT=7
_bash_modern_abbr_expand
[[ ${READLINE_LINE} == 'sudo git status --short' ]]
[[ ${READLINE_POINT} -eq 15 ]]
READLINE_LINE='/tmp/gs'
READLINE_POINT=7
_bash_modern_abbr_expand
[[ ${READLINE_LINE} == '/tmp/gs' ]]
abbr --add ab 'echo expanded'
READLINE_LINE='abbr --erase ab'
READLINE_POINT=${#READLINE_LINE}
_bash_modern_abbr_expand
[[ ${READLINE_LINE} == 'abbr --erase ab' ]]
READLINE_LINE='printf done; abbr --erase ab'
READLINE_POINT=${#READLINE_LINE}
_bash_modern_abbr_expand
[[ ${READLINE_LINE} == 'printf done; abbr --erase ab' ]]
READLINE_LINE='echo ab'
READLINE_POINT=${#READLINE_LINE}
_bash_modern_abbr_expand
[[ ${READLINE_LINE} == 'echo echo expanded' ]]
abbr --erase ab
[[ -f "${BASH_MODERN_HOME}/user/abbreviations.bash" ]]
chmod 666 "${BASH_MODERN_HOME}/user/abbreviations.bash"
(
    source "${BASH_MODERN_HOME}/bashrc.d/40-abbreviations.sh" 2>/dev/null
    [[ ${#_BASH_MODERN_ABBR_NAMES[@]} -eq 0 ]]
)
chmod 600 "${BASH_MODERN_HOME}/user/abbreviations.bash"

source "${BASH_MODERN_HOME}/bashrc.d/45-command-library.sh"
declare -F dc >/dev/null
declare -F dcup >/dev/null
declare -F dlogs >/dev/null
[[ $(_bash_modern_abbr_find mtr100) -ge 0 ]]
grep -Fq 'dlogs [service] [lines]' <(cmds docker)
grep -Fq 'dc <compose-arguments...>' <(cmds docker)
grep -Fq 'local args=(sudo docker compose)' "${BASH_MODERN_HOME}/commands.d/20-common.sh"
grep -Fq 'dc pull && dc up -d --remove-orphans' "${BASH_MODERN_HOME}/commands.d/20-common.sh"
(
    compose_test_dir="${TEST_ROOT}/compose"
    mkdir -p "${compose_test_dir}"
    touch "${compose_test_dir}/env.defaults" "${compose_test_dir}/.env"
    sudo() { printf '<%s>\n' "$@"; }
    cd "${compose_test_dir}"
    [[ $(dc ps) == $'<docker>\n<compose>\n<--env-file>\n<env.defaults>\n<--env-file>\n<.env>\n<ps>' ]]
)
grep -Fq 'mtr100 <host>' <(cmds mtr)
grep -Fq "${BASH_MODERN_HOME}/commands.d/20-common.sh" <(cmds --sources)

abbr --add mtr100 custom mtr
source "${BASH_MODERN_HOME}/commands.d/30-abbreviations.sh"
index=$(_bash_modern_abbr_find mtr100)
[[ ${_BASH_MODERN_ABBR_VALUES[index]} == 'custom mtr' ]]
! grep -Fq 'dcup' "${BASH_MODERN_HOME}/user/abbreviations.bash"
abbr --erase mtr100
index=$(_bash_modern_abbr_find mtr100)
[[ ${_BASH_MODERN_ABBR_VALUES[index]} == 'mtr -rwzc 100 -4' ]]

mkdir -p "${HOME}/.config/bash-modern-commands/commands.d"
cp "${ROOT_DIR}/examples/private-commands/abbreviations.sh" "${HOME}/.config/bash-modern-commands/abbreviations.sh"
cp "${ROOT_DIR}/examples/private-commands/commands.d/services.sh" "${HOME}/.config/bash-modern-commands/commands.d/services.sh"
chmod -R go-w "${HOME}/.config/bash-modern-commands"
source "${BASH_MODERN_HOME}/bashrc.d/45-command-library.sh"
declare -F service-status >/dev/null
grep -Fq 'service-status <name>' <(cmds services)
grep -Fq "${HOME}/.config/bash-modern-commands/abbreviations.sh" <(cmds --sources)
index=$(_bash_modern_abbr_find curl-private)
[[ ${_BASH_MODERN_ABBR_VALUES[index]} == 'curl --fail --show-error https://service.example.internal' ]]
printf 'unsafe-command() { :; }\n' >"${HOME}/.config/bash-modern-commands/commands.d/unsafe.sh"
chmod 666 "${HOME}/.config/bash-modern-commands/commands.d/unsafe.sh"
(
    source "${BASH_MODERN_HOME}/bashrc.d/45-command-library.sh" 2>/dev/null
    ! declare -F unsafe-command >/dev/null
)

printf '# @cmd Local | only-here | Test a host-only command\nonly-here() { :; }\n' >"${BASH_MODERN_HOME}/user/local.sh"
chmod 600 "${BASH_MODERN_HOME}/user/local.sh"

(
    source "${BASH_MODERN_HOME}/bashrc.d/35-native-prompt.sh"
    set +o errexit
    false
    _bash_modern_prompt_update
    [[ ${PS1} == *'[1]'* ]]
)

if command -v git >/dev/null 2>&1; then
    (
        prompt_repo="${TEST_ROOT}/prompt-repo"
        mkdir -p "${prompt_repo}"
        touch "${BASH_MODERN_HOME}/user/git-status.enabled"
        source "${BASH_MODERN_HOME}/bashrc.d/35-native-prompt.sh"
        cd "${prompt_repo}"
        git init -q
        git config user.email test@example.com
        git config user.name test
        git config commit.gpgsign false
        touch tracked
        git add tracked
        git commit -qm initial
        branch=$(git branch --show-current)
        touch dirty
        git_prompt=$(_bash_modern_git_prompt)
        [[ ${git_prompt} == *"${branch}"*'*'* ]]
        git checkout --detach -q
        git_prompt=$(_bash_modern_git_prompt)
        [[ ${git_prompt} == *"$(git rev-parse --short=8 HEAD)"* ]]
    )
    rm -f "${BASH_MODERN_HOME}/user/git-status.enabled"
fi

mkdir -p "${BASH_MODERN_HOME}/vendor/blesh"
touch "${BASH_MODERN_HOME}/vendor/blesh/ble.sh"
printf '#!/bin/sh\nexit 0\n' >"${BASH_MODERN_HOME}/bin/starship"
printf '#!/bin/sh\nexit 0\n' >"${BASH_MODERN_HOME}/bin/zoxide"
chmod +x "${BASH_MODERN_HOME}/bin/starship" "${BASH_MODERN_HOME}/bin/zoxide"
mkdir -p "${BASH_MODERN_HOME}/share/man/man1"
touch "${BASH_MODERN_HOME}/share/man/man1/zoxide.1"
"${ROOT_DIR}/install.sh" --skip-downloads --starship --git-status >/dev/null
[[ "$(grep -Fc '# >>> bash-modern-server >>>' "${BASH_MODERN_BASHRC}")" -eq 1 ]]
[[ ! -d "${BASH_MODERN_HOME}/vendor/blesh" ]]
[[ -x "${BASH_MODERN_HOME}/bin/starship" ]]
[[ -x "${BASH_MODERN_HOME}/bin/zoxide" ]]
[[ -f "${BASH_MODERN_HOME}/share/man/man1/zoxide.1" ]]
[[ -f "${BASH_MODERN_HOME}/user/starship.enabled" ]]
[[ -f "${BASH_MODERN_HOME}/user/git-status.enabled" ]]
grep -Fq 'only-here()' "${BASH_MODERN_HOME}/user/local.sh"
grep -Fq '_BASH_MODERN_ABBR_NAMES[0]=gs' "${BASH_MODERN_HOME}/user/abbreviations.bash"

"${ROOT_DIR}/install.sh" --skip-downloads >/dev/null
[[ -x "${BASH_MODERN_HOME}/bin/starship" ]]
[[ -f "${BASH_MODERN_HOME}/user/starship.enabled" ]]
[[ -f "${BASH_MODERN_HOME}/user/git-status.enabled" ]]

"${ROOT_DIR}/install.sh" --skip-downloads --no-starship --no-git-status >/dev/null
[[ ! -x "${BASH_MODERN_HOME}/bin/starship" ]]
[[ ! -f "${BASH_MODERN_HOME}/user/starship.enabled" ]]
[[ ! -f "${BASH_MODERN_HOME}/user/git-status.enabled" ]]
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
