# @cmd Services | service-status <name> | Show a private service status
service-status() {
    local service=${1:-}
    [[ -n ${service} ]] || { printf 'usage: service-status <name>\n' >&2; return 2; }
    systemctl status "${service}"
}
