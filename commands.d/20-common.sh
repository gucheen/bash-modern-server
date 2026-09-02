# @cmd Docker | dc <compose-arguments...> | Run Docker Compose with sudo and project env files
dc() {
    local args=(sudo docker compose)

    [[ -f env.defaults ]] && args+=(--env-file env.defaults)
    [[ -f .env ]] && args+=(--env-file .env)

    "${args[@]}" "$@"
}

# @cmd Docker | dcup | Pull images and recreate the current Compose project
dcup() {
    dc pull && dc up -d --remove-orphans
}

# @cmd Docker | dlogs [service] [lines] | Follow Compose logs, showing 100 lines by default
dlogs() {
    local service=${1:-} lines=${2:-100}
    [[ ${lines} =~ ^[0-9]+$ ]] || {
        printf 'usage: dlogs [service] [lines]\n' >&2
        return 2
    }
    if [[ -n ${service} ]]; then
        dc logs --tail "${lines}" -f "${service}"
    else
        dc logs --tail "${lines}" -f
    fi
}

# @cmd Network | ports | Show listening TCP and UDP sockets
ports() {
    ss -lntup
}

# @cmd System | mem | Show memory usage in human-readable units
mem() {
    free -h
}

# @cmd System | journal <service> [lines] | Follow a systemd unit log
journal() {
    local service=${1:-} lines=${2:-100}
    [[ -n ${service} && ${lines} =~ ^[0-9]+$ ]] || {
        printf 'usage: journal <service> [lines]\n' >&2
        return 2
    }
    journalctl -u "${service}" -n "${lines}" -f
}
