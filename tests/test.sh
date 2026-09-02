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
grep -Fq 'format = "$username$hostname$directory$cmd_duration$status$character"' "${BASH_MODERN_HOME}/starship.toml"
grep -Fq 'format = "$username$hostname$directory$git_branch$git_status$cmd_duration$status$character"' "${BASH_MODERN_HOME}/starship-git.toml"
grep -Fq "success_symbol = '[\\\$](green) '" "${BASH_MODERN_HOME}/starship.toml"
! grep -Fq 'PROMPT_COMMAND="history -a; history -n' "${BASH_MODERN_HOME}/bashrc.d/00-history.sh"
[[ ! -e "${BASH_MODERN_HOME}/bashrc.d/90-blesh.sh" ]]
[[ ! -d "${BASH_MODERN_HOME}/vendor/blesh" ]]
grep -Fq 'backward-kill-word' "${BASH_MODERN_HOME}/bashrc.d/10-shell-options.sh"
[[ -f "${BASH_MODERN_HOME}/bashrc.d/99-zoxide.sh" ]]
[[ -f "${BASH_MODERN_HOME}/bashrc.d/40-abbreviations.sh" ]]
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
[[ -f "${BASH_MODERN_HOME}/user/abbreviations.bash" ]]

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
