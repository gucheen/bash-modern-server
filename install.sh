#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${ROOT_DIR}/lib/common.sh"

DOWNLOADS=1
OPTIONAL_TOOLS=0
UPDATE=0

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --skip-downloads   Install configuration only; use tools already in PATH.
  --optional-tools   Install eza/bat/fd/rg with apt (sudo may be requested).
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
        --update) UPDATE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
    shift
done

validate_paths
command -v bash >/dev/null 2>&1 || die "bash is required"
backup="$(create_backup)"
info "Backup saved to ${backup}"

stage="${CONFIG_DIR}.stage.$$"
rm -rf "${stage}"
mkdir -p "${stage}/bashrc.d" "${stage}/bin" "${stage}/vendor" "${stage}/share/man"
cp "${ROOT_DIR}/config/bashrc" "${stage}/bashrc"
cp "${ROOT_DIR}/config/starship.toml" "${stage}/starship.toml"
cp "${ROOT_DIR}"/bashrc.d/*.sh "${stage}/bashrc.d/"
cp "${ROOT_DIR}"/bin/* "${stage}/bin/"
chmod +x "${stage}/bin/"*

if [[ -d "${CONFIG_DIR}/vendor" ]]; then
    cp -a "${CONFIG_DIR}/vendor/." "${stage}/vendor/"
fi
rm -rf "${stage}/vendor/blesh"
for preserved_binary in starship zoxide; do
    if [[ -x "${CONFIG_DIR}/bin/${preserved_binary}" ]]; then
        cp -p "${CONFIG_DIR}/bin/${preserved_binary}" "${stage}/bin/${preserved_binary}"
    fi
done
unset preserved_binary
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
    for component in fzf zoxide starship; do
        if ! "install_${component}"; then
            warn "Could not install ${component}; configuration will use it automatically when available"
            download_failures=$((download_failures + 1))
        fi
    done
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
