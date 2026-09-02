#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/lib/common.sh"

DOWNLOADS=1
OPTIONAL_TOOLS=0
INSTALL_DEPS=0
UPDATE=0
STARSHIP_MODE=keep
GIT_STATUS_MODE=keep

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --skip-downloads   Install configuration only; use tools already in PATH.
  --optional-tools   Install eza/bat/fd/rg with apt (sudo may be requested).
  --install-deps     Install autosuggestions build dependencies with apt.
  --starship         Use and install Starship instead of the native prompt.
  --no-starship      Use the native Bash prompt and remove managed Starship.
  --git-status       Show Git branch and working-tree status in the prompt.
  --no-git-status    Do not query Git while drawing the prompt.
  --update           Refresh downloaded integrations.
  -h, --help         Show this help.

Environment overrides:
  BASH_MODERN_HOME, BASH_MODERN_BACKUP_ROOT, BASH_MODERN_BASHRC
EOF
}

while (($#)); do
    case "$1" in
        --skip-downloads) DOWNLOADS=0 ;;
        --optional-tools) OPTIONAL_TOOLS=1 ;;
        --install-deps) INSTALL_DEPS=1 ;;
        --starship) STARSHIP_MODE=enable ;;
        --no-starship) STARSHIP_MODE=disable ;;
        --git-status) GIT_STATUS_MODE=enable ;;
        --no-git-status) GIT_STATUS_MODE=disable ;;
        --update) UPDATE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

validate_paths
command -v bash >/dev/null 2>&1 || die "bash is required"
if [[ ${INSTALL_DEPS} -eq 1 ]]; then
    BASH_MODERN_HOME="${CONFIG_DIR}" BASH_MODERN_BACKUP_ROOT="${BACKUP_ROOT}" \
        BASH_MODERN_BASHRC="${BASHRC_FILE}" "${ROOT_DIR}/bin/bash-modern" install-build-deps
fi
backup="$(create_backup)"
info "Backup saved to ${backup}"

stage="${CONFIG_DIR}.stage.$$"
rm -rf "${stage}"
mkdir -p "${stage}/bashrc.d" "${stage}/commands.d" "${stage}/bin" "${stage}/vendor" "${stage}/share/man" "${stage}/user"
cp "${ROOT_DIR}/config/bashrc" "${stage}/bashrc"
cp "${ROOT_DIR}/config/starship.toml" "${stage}/starship.toml"
cp "${ROOT_DIR}/config/starship-git.toml" "${stage}/starship-git.toml"
cp "${ROOT_DIR}"/bashrc.d/*.sh "${stage}/bashrc.d/"
cp "${ROOT_DIR}"/commands.d/*.sh "${stage}/commands.d/"
cp "${ROOT_DIR}"/bin/* "${stage}/bin/"
chmod +x "${stage}/bin/"*

if [[ -d "${CONFIG_DIR}/vendor" ]]; then
    cp -a "${CONFIG_DIR}/vendor/." "${stage}/vendor/"
fi
rm -rf "${stage}/vendor/blesh"
if [[ -d "${CONFIG_DIR}/user" ]]; then
    cp -a "${CONFIG_DIR}/user/." "${stage}/user/"
fi
chmod go-w "${stage}/user"
case ${STARSHIP_MODE} in
    enable) touch "${stage}/user/starship.enabled" ;;
    disable) rm -f "${stage}/user/starship.enabled" ;;
esac
case ${GIT_STATUS_MODE} in
    enable) touch "${stage}/user/git-status.enabled" ;;
    disable) rm -f "${stage}/user/git-status.enabled" ;;
esac

for preserved_binary in zoxide; do
    if [[ -x "${CONFIG_DIR}/bin/${preserved_binary}" ]]; then
        cp -p "${CONFIG_DIR}/bin/${preserved_binary}" "${stage}/bin/${preserved_binary}"
    fi
done
unset preserved_binary
if [[ -f "${stage}/user/starship.enabled" && -x "${CONFIG_DIR}/bin/starship" ]]; then
    cp -p "${CONFIG_DIR}/bin/starship" "${stage}/bin/starship"
fi
if [[ -d "${CONFIG_DIR}/share/man" ]]; then
    cp -a "${CONFIG_DIR}/share/man/." "${stage}/share/man/"
fi

fetch() {
    local url=$1 destination=$2
    if command -v curl >/dev/null 2>&1; then
        curl --fail --location --silent --show-error "$url" --output "$destination"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$url" -O "$destination"
    else
        return 1
    fi
}

install_fzf() {
    local target="${stage}/vendor/fzf"
    [[ ${UPDATE} -eq 1 ]] && rm -rf "${target}"
    [[ -x "${target}/bin/fzf" ]] && return 0
    command -v git >/dev/null 2>&1 || return 1
    info "Installing fzf"
    rm -rf "${target}"
    git clone --depth 1 https://github.com/junegunn/fzf.git "${target}" || return 1
    "${target}/install" --bin || return 1
}

install_bash_autosuggestions() {
    local target="${stage}/vendor/bash-autosuggestions" built_for bash_include
    built_for=
    [[ -r "${target}/.bash-version" ]] && built_for=$(<"${target}/.bash-version")
    [[ ${UPDATE} -eq 1 ]] && rm -rf "${target}"
    if [[ ${built_for} == "${BASH_VERSION}" && -r "${target}/bash-autosuggestions.bash" &&
          -f "${target}/bash-autosuggestions.so" ]]; then
        return 0
    fi
    rm -rf "${target}"
    if ! command -v git >/dev/null 2>&1 || ! command -v make >/dev/null 2>&1 ||
       ! command -v cc >/dev/null 2>&1 || ! command -v pkg-config >/dev/null 2>&1; then
        warn "bash-autosuggestions build tools are missing; rerun with --install-deps"
        return 1
    fi
    bash_include=$(pkg-config --variable=includedir bash 2>/dev/null || true)
    if [[ ! -r "${bash_include}/bash/builtins.h" ]] ||
       ! pkg-config --exists readline 2>/dev/null; then
        warn "bash-autosuggestions headers are missing; rerun with --install-deps"
        return 1
    fi
    info "Installing bash-autosuggestions"
    if ! git clone --depth 1 https://github.com/wallentx/bash-autosuggestions.git "${target}" ||
       ! make -C "${target}" all BASH_INCLUDE="${bash_include}"; then
        rm -rf "${target}"
        return 1
    fi
    printf '%s\n' "${BASH_VERSION}" >"${target}/.bash-version"
}

install_zoxide() {
    [[ ${UPDATE} -eq 0 && -x "${stage}/bin/zoxide" ]] && return 0
    info "Installing zoxide"
    local installer="${stage}/.zoxide-install.sh"
    fetch "https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh" "${installer}" || return 1
    sh "${installer}" --bin-dir "${stage}/bin" --man-dir "${stage}/share/man" --sudo false
    rm -f "${installer}"
}

install_starship() {
    [[ ${UPDATE} -eq 0 && -x "${stage}/bin/starship" ]] && return 0
    info "Installing Starship"
    local installer="${stage}/.starship-install.sh"
    fetch "https://raw.githubusercontent.com/starship/starship/master/install/install.sh" "${installer}" || return 1
    sh "${installer}" --yes --bin-dir "${stage}/bin"
    rm -f "${installer}"
}

if [[ ${DOWNLOADS} -eq 1 ]]; then
    download_failures=0
    components=(fzf bash_autosuggestions zoxide)
    [[ -f "${stage}/user/starship.enabled" ]] && components+=(starship)
    for component in "${components[@]}"; do
        if ! "install_${component}"; then
            warn "Could not install ${component//_/-}; configuration will use it automatically when available"
            download_failures=$((download_failures + 1))
        fi
    done
    unset components component
fi

rm -rf "${CONFIG_DIR}"
mv "${stage}" "${CONFIG_DIR}"

mkdir -p "$(dirname "${BASHRC_FILE}")"
touch "${BASHRC_FILE}"
tmp_bashrc="${BASHRC_FILE}.tmp.$$"
strip_managed_block "${BASHRC_FILE}" "${tmp_bashrc}"
while [[ -s "${tmp_bashrc}" && "$(tail -c 1 "${tmp_bashrc}" | wc -l)" -eq 0 ]]; do printf '\n' >>"${tmp_bashrc}"; done
cat >>"${tmp_bashrc}" <<EOF
${BEGIN_MARKER}
export BASH_MODERN_HOME="${CONFIG_DIR}"
[[ -r "\${BASH_MODERN_HOME}/bashrc" ]] && source "\${BASH_MODERN_HOME}/bashrc"
${END_MARKER}
EOF
mv "${tmp_bashrc}" "${BASHRC_FILE}"

if [[ ${OPTIONAL_TOOLS} -eq 1 ]]; then
    "${CONFIG_DIR}/bin/bash-modern" install-optional
fi

info "Installation complete"
printf 'Start a new SSH session or run: exec bash\n'
printf 'Check status with: %q doctor\n' "${CONFIG_DIR}/bin/bash-modern"
if [[ ${DOWNLOADS} -eq 1 && ${download_failures} -gt 0 ]]; then
    warn "${download_failures} integration(s) were skipped; rerun the installer after fixing network or dependencies"
    exit 2
fi
