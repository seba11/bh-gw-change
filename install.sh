#!/bin/bash

INSTALL_DIR="/usr/local/sbin/bh-gw-change"
SERVICE_NAME="bh-gw-change.service"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
DEFAULTS_FILE="/etc/default/bh-gw-change"

DEFAULT_INTERFACE="vlan666"
DEFAULT_PORT="666"
DEFAULT_FIREWALL_CONFIG="/etc/firewall/rc.fire_conf"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_APP_DIR="${SCRIPT_DIR}/usr/local/sbin/bh-gw-change"
SOURCE_SERVICE_FILE="${SCRIPT_DIR}/etc/systemd/system/${SERVICE_NAME}"

error() {
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo "==> $*"
}

require_command() {
    command -v "$1" >/dev/null 2>&1 ||
        error "Required command not found: $1"
}

get_interface_ipv4() {
    ip -4 -o addr show dev "$1" scope global 2>/dev/null |
        awk 'NR == 1 { split($4, address, "/"); print address[1] }'
}

validate_ipv4() {
    local address="$1"
    local octet
    local -a octets

    [[ "$address" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1

    IFS='.' read -r -a octets <<< "$address"
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        (( 10#$octet <= 255 )) || return 1
    done
}

if (( EUID != 0 )); then
    error "This installer must be run as root, for example: sudo ./install.sh"
fi

for command in install ln ip awk php systemctl; do
    require_command "$command"
done

[[ -f "${SOURCE_APP_DIR}/bh-gw-change.php" ]] ||
    error "File not found: ${SOURCE_APP_DIR}/bh-gw-change.php"

[[ -f "${SOURCE_APP_DIR}/config_vars.sh" ]] ||
    error "File not found: ${SOURCE_APP_DIR}/config_vars.sh"

[[ -f "$SOURCE_SERVICE_FILE" ]] ||
    error "File not found: $SOURCE_SERVICE_FILE"

DEFAULT_LISTEN_ADDRESS="$(get_interface_ipv4 "$DEFAULT_INTERFACE")"

echo
echo "bh-gw-change installation"
echo

if [[ -n "$DEFAULT_LISTEN_ADDRESS" ]]; then
    read -r -p "Listen IPv4 address [${DEFAULT_LISTEN_ADDRESS}]: " LISTEN_ADDRESS
    LISTEN_ADDRESS="${LISTEN_ADDRESS:-$DEFAULT_LISTEN_ADDRESS}"
else
    echo "No IPv4 address was found on interface ${DEFAULT_INTERFACE}."
    read -r -p "Enter the listen IPv4 address: " LISTEN_ADDRESS
fi

validate_ipv4 "$LISTEN_ADDRESS" ||
    error "Invalid IPv4 address: $LISTEN_ADDRESS"

read -r -p "Listen port [${DEFAULT_PORT}]: " LISTEN_PORT
LISTEN_PORT="${LISTEN_PORT:-$DEFAULT_PORT}"

[[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] ||
    error "Invalid port: $LISTEN_PORT"

(( LISTEN_PORT >= 1 && LISTEN_PORT <= 65535 )) ||
    error "Port must be between 1 and 65535."

read -r -p "Firewall configuration file [${DEFAULT_FIREWALL_CONFIG}]: " FIREWALL_CONFIG
FIREWALL_CONFIG="${FIREWALL_CONFIG:-$DEFAULT_FIREWALL_CONFIG}"

[[ -f "$FIREWALL_CONFIG" ]] ||
    error "Firewall configuration file does not exist: $FIREWALL_CONFIG"

info "Creating application directory"
install -d -o root -g root -m 0755 "$INSTALL_DIR"

info "Installing application files"
install -o root -g root -m 0644 \
    "${SOURCE_APP_DIR}/bh-gw-change.php" \
    "${INSTALL_DIR}/bh-gw-change.php"

install -o root -g root -m 0755 \
    "${SOURCE_APP_DIR}/config_vars.sh" \
    "${INSTALL_DIR}/config_vars.sh"

info "Creating firewall configuration symlink"
ln -sfn "$FIREWALL_CONFIG" "${INSTALL_DIR}/rc.fire_conf"

info "Creating service configuration"
install -d -o root -g root -m 0755 /etc/default

cat > "$DEFAULTS_FILE" <<EOF
LISTEN_ADDRESS=${LISTEN_ADDRESS}
LISTEN_PORT=${LISTEN_PORT}
EOF

chown root:root "$DEFAULTS_FILE"
chmod 0644 "$DEFAULTS_FILE"

info "Installing systemd service unit"
install -o root -g root -m 0644 \
    "$SOURCE_SERVICE_FILE" \
    "$SERVICE_FILE"

info "Reloading systemd configuration"
systemctl daemon-reload

info "Enabling and restarting ${SERVICE_NAME}"
systemctl enable "$SERVICE_NAME" >/dev/null
systemctl restart "$SERVICE_NAME"

if ! systemctl is-active --quiet "$SERVICE_NAME"; then
    systemctl --no-pager --full status "$SERVICE_NAME" || true
    error "The service failed to start."
fi

echo
echo "Installation completed successfully."
echo "Listen address:         http://${LISTEN_ADDRESS}:${LISTEN_PORT}"
echo "Application directory:  ${INSTALL_DIR}"
echo "Service configuration:  ${DEFAULTS_FILE}"
echo "Firewall configuration: ${FIREWALL_CONFIG}"
echo
systemctl --no-pager --full status "$SERVICE_NAME"
