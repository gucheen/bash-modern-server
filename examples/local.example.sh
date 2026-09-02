# This file is a template. Copy it to:
#   ~/.config/bash-modern/user/local.sh
# Then restrict it with: chmod 600 ~/.config/bash-modern/user/local.sh

BMS_COMPOSE_ROOT=/opt/docker

# @cmd Local | app-logs <app> [lines] | Follow logs for an app stored below BMS_COMPOSE_ROOT
app-logs() {
    local app=${1:-} lines=${2:-100} app_directory
    [[ -n ${app} && ${app} != . && ${app} != .. && ${app} != */* && ${lines} =~ ^[0-9]+$ ]] || {
        printf 'usage: app-logs <app> [lines]\n' >&2
        return 2
    }
    app_directory=${BMS_COMPOSE_ROOT}/${app}
    (
        cd "${app_directory}" || return
        dc -f compose.yml logs --tail "${lines}" -f
    )
}
