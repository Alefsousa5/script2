#!/usr/bin/env bash
#
# install.sh — Instala o Xray na VPS e cria a configuração inicial rodando
#              para as operadoras (foco inicial: TIM).
#
# Uso:
#   sudo bash install.sh
#   sudo bash install.sh --port 443
#   sudo bash install.sh --port 8080 --uuid <seu-uuid> --protocol vmess
#
# Variáveis aceitas via argumento:
#   --port        Porto dos inbounds (padrão: 8080)
#   --uuid        UUID a usar nos inbounds (padrão: gerado automaticamente)
#   --protocol    Protocolo principal: vless ou vmess (padrão: vless)
#   --no-color    Desativa cores na saída
#
set -euo pipefail

# --------------------------------------------------------------------------- #
# Caminho deste script                                                         #
# --------------------------------------------------------------------------- #
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --------------------------------------------------------------------------- #
# Configurações padrão                                                        #
# --------------------------------------------------------------------------- #
XRAY_VERSION="latest"                 # versão do Xray (latest ou vX.Y.Z)
XRAY_USER="xray"
XRAY_DIR="/usr/local/etc/xray"
XRAY_BIN="/usr/local/bin/xray"
XRAY_LOG_DIR="/var/log/xray"
XRAY_SERVICE="/etc/systemd/system/xray.service"
DEFAULT_PORT="8080"
DEFAULT_PROTOCOL="vless"

USE_COLOR="1"
PORT="$DEFAULT_PORT"
UUID=""
PROTOCOL="$DEFAULT_PROTOCOL"

# --------------------------------------------------------------------------- #
# Cores para o terminal                                                        #
# --------------------------------------------------------------------------- #
if [[ -t 1 && "${NO_COLOR:-}" != "1" ]]; then
    USE_COLOR="1"
else
    USE_COLOR="0"
fi

c_green()  { [[ "$USE_COLOR" == "1" ]] && printf "\033[0;32m%s\033[0m" "$1" || printf "%s" "$1"; }
c_red()    { [[ "$USE_COLOR" == "1" ]] && printf "\033[0;31m%s\033[0m" "$1" || printf "%s" "$1"; }
c_yellow() { [[ "$USE_COLOR" == "1" ]] && printf "\033[0;33m%s\033[0m" "$1" || printf "%s" "$1"; }
c_cyan()   { [[ "$USE_COLOR" == "1" ]] && printf "\033[0;36m%s\033[0m" "$1" || printf "%s" "$1"; }
c_bold()   { [[ "$USE_COLOR" == "1" ]] && printf "\033[1m%s\033[0m" "$1" || printf "%s" "$1"; }

info()  { printf '%s\n' "$(c_green '[*]') $*"; }
warn()  { printf '%s\n' "$(c_yellow '[!]') $*"; }
error() { printf '%s\n' "$(c_red '[x]') $*" >&2; }
die()   { error "$*"; exit 1; }

# --------------------------------------------------------------------------- #
# Help                                                                        #
# --------------------------------------------------------------------------- #
usage() {
    cat <<EOF
$(c_bold "install.sh") — Instala o Xray e cria os inbounds na VPS.

$(c_bold "Uso:") sudo bash install.sh [opções]

$(c_bold "Opções:")
  --port <porta>        Porto dos inbounds (padrão: $DEFAULT_PORT)
  --uuid <uuid>         UUID a usar nos inbounds (padrão: gerado automaticamente)
  --protocol <proto>    Protocolo principal: vless ou vmess (padrão: $DEFAULT_PROTOCOL)
  --no-color            Desativa as cores
  -h, --help            Mostra esta ajuda

$(c_bold "Exemplos:")
  sudo bash install.sh
  sudo bash install.sh --port 443
  sudo bash install.sh --port 8080 --uuid "00000000-0000-0000-0000-000000000000"
EOF
}

# --------------------------------------------------------------------------- #
# Parse de argumentos                                                         #
# --------------------------------------------------------------------------- #
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --port)
                [[ -z "${2:-}" ]] && die "Faltou o valor de --port"
                local p="$2"
                if ! [[ "$p" =~ ^[0-9]+$ ]] || (( p < 1 || p > 65535 )); then
                    die "Porta inválida: $2"
                fi
                if (( p > 65534 )); then
                    die "A porta máx. é 65534, pois o segundo inbound usa a porta $((p + 1))"
                fi
                PORT="$p"
                shift 2
                ;;
            --uuid)
                [[ -z "${2:-}" ]] && die "Faltou o valor de --uuid"
                UUID="$2"
                shift 2
                ;;
            --protocol)
                [[ -z "${2:-}" ]] && die "Faltou o valor de --protocol"
                PROTOCOL="${2,,}"
                if [[ "$PROTOCOL" != "vless" && "$PROTOCOL" != "vmess" ]]; then
                    die "Protocolo inválido: $2 (use vless ou vmess)"
                fi
                shift 2
                ;;
            --no-color)
                USE_COLOR="0"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                die "Opção desconhecida: $1 (use --help para ajuda)"
                ;;
        esac
    done
}

# --------------------------------------------------------------------------- #
# Verificações iniciais                                                       #
# --------------------------------------------------------------------------- #
require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "Este script precisa de privilégios de root. Execute: sudo bash install.sh"
    fi
}

have_cmd() {
    command -v "$1" >/dev/null 2>&1
}

check_commands() {
    local missing=()
    for cmd in curl unzip jq; do
        have_cmd "$cmd" || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Faltam dependências: ${missing[*]}"
        info "Tentando instalar as dependências automaticamente..."
        if have_cmd apt-get; then
            DEBIAN_FRONTEND=noninteractive apt-get update -y
            DEBIAN_FRONTEND=noninteractive apt-get install -y curl unzip jq
        elif have_cmd dnf; then
            dnf install -y curl unzip jq
        elif have_cmd yum; then
            yum install -y curl unzip jq
        elif have_cmd apk; then
            apk add --no-cache curl unzip jq
        else
            die "Não foi possível instalar as dependências (curl/unzip/jq). Instale manualmente e rode novamente."
        fi
    fi
}

# --------------------------------------------------------------------------- #
# Detectar arquitetura                                                        #
# --------------------------------------------------------------------------- #
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)  echo "64" ;;
        i386|i686)     echo "32" ;;
        aarch64|arm64) echo "arm64-v8a" ;;
        armv7l|armv7)  echo "arm32-v7a" ;;
        *) die "Arquitetura não suportada: $arch" ;;
    esac
}

# --------------------------------------------------------------------------- #
# Obter versão do Xray                                                         #
# --------------------------------------------------------------------------- #
resolve_version() {
    if [[ "$XRAY_VERSION" == "latest" ]]; then
        local ver
        ver="$(curl -fsSL "https://api.github.com/repos/XTLS/Xray-core/releases/latest" \
            | grep '"tag_name"' | head -n1 | sed -E 's/.*"tag_name"\s*:\s*"([^"]+)".*/\1/')"
        [[ -z "$ver" ]] && die "Não consegui descobrir a versão mais recente do Xray."
        echo "$ver"
    else
        echo "$XRAY_VERSION"
    fi
}

# --------------------------------------------------------------------------- #
# Fazer download e instalar os binários do Xray                                #
# --------------------------------------------------------------------------- #
install_xray() {
    local arch ver url tmpdir install_dir
    arch="$(detect_arch)"
    ver="$(resolve_version)"

    info "Baixando Xray $ver (arquitetura: $arch)..."

    url="https://github.com/XTLS/Xray-core/releases/download/${ver}/Xray-linux-${arch}.zip"
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    if ! curl -fsSL --retry 3 -o "$tmpdir/xray.zip" "$url"; then
        die "Falha ao baixar $url"
    fi

    if ! unzip -o "$tmpdir/xray.zip" -d "$tmpdir" >/dev/null; then
        die "Falha ao extrair o arquivo baixado."
    fi

    install_dir="/usr/local/bin"
    mkdir -p "$install_dir"

    if [[ ! -f "$tmpdir/xray" ]]; then
        die "Binário 'xray' não encontrado no pacote baixado."
    fi

    install -m 0755 "$tmpdir/xray" "$XRAY_BIN"

    # Arquivos de geo (podem vir no mesmo zip)
    if [[ -f "$tmpdir/geoip.dat" ]]; then
        install -m 0644 "$tmpdir/geoip.dat" "$XRAY_DIR/geoip.dat" 2>/dev/null || true
    fi
    if [[ -f "$tmpdir/geosite.dat" ]]; then
        install -m 0644 "$tmpdir/geosite.dat" "$XRAY_DIR/geosite.dat" 2>/dev/null || true
    fi

    "$XRAY_BIN" version >/dev/null 2>&1 || die "O binário do Xray não está funcionando corretamente."

    # Garante que os arquivos de geo existam (podem não vir no zip).
    local geo_missing=0
    [[ -f "$XRAY_DIR/geoip.dat" ]] || geo_missing=1
    if [[ "$geo_missing" == "1" ]]; then
        info "Baixando geoip.dat..."
        if curl -fsSL --retry 3 -o "$XRAY_DIR/geoip.dat" \
            "https://github.com/XTLS/Xray-core/releases/download/${ver}/geoip.dat"; then
            chmod 644 "$XRAY_DIR/geoip.dat"
        else
            warn "Não foi possível baixar geoip.dat. A regra de rotas privadas será desabilitada."
            rm -f "$XRAY_DIR/geoip.dat"
        fi
    fi

    if [[ ! -f "$XRAY_DIR/geosite.dat" ]]; then
        info "Baixando geosite.dat..."
        if curl -fsSL --retry 3 -o "$XRAY_DIR/geosite.dat" \
            "https://github.com/XTLS/Xray-core/releases/download/${ver}/geosite.dat"; then
            chmod 644 "$XRAY_DIR/geosite.dat"
        else
            warn "Não foi possível baixar geosite.dat."
            rm -f "$XRAY_DIR/geosite.dat"
        fi
    fi

    info "Xray instalado em $XRAY_BIN (versão $ver)."
}

# --------------------------------------------------------------------------- #
# Instalar o menu de gerenciamento                                            #
# --------------------------------------------------------------------------- #
install_menu() {
    local menu_src="$SCRIPT_DIR/menu.sh"
    if [[ ! -f "$menu_src" ]]; then
        warn "menu.sh não encontrado em $menu_src — o menu não será instalado."
        return
    fi
    install -m 0755 "$menu_src" /usr/local/sbin/xray-menu
    info "Menu instalado: /usr/local/sbin/xray-menu (execute com: sudo xray-menu)"
}

# --------------------------------------------------------------------------- #
# Criar usuário e diretórios                                                  #
# --------------------------------------------------------------------------- #
setup_user_and_dirs() {
    if ! id "$XRAY_USER" >/dev/null 2>&1; then
        if have_cmd useradd; then
            useradd -r -M -s /usr/sbin/nologin "$XRAY_USER"
        else
            useradd -r -s /usr/sbin/nologin "$XRAY_USER"
        fi
    fi

    mkdir -p "$XRAY_DIR" "$XRAY_LOG_DIR"
    chown -R "$XRAY_USER:$XRAY_USER" "$XRAY_DIR" "$XRAY_LOG_DIR"
    chmod 755 "$XRAY_DIR" "$XRAY_LOG_DIR"
}

# --------------------------------------------------------------------------- #
# Gerar UUID                                                                  #
# --------------------------------------------------------------------------- #
generate_uuid() {
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
        return
    fi
    if have_cmd openssl; then
        openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
        return
    fi
    if have_cmd python3; then
        python3 -c 'import uuid; print(uuid.uuid4())'
        return
    fi
    die "Não foi possível gerar um UUID automaticamente. Passe um com --uuid."
}

validate_uuid() {
    if ! [[ "$UUID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
        die "UUID inválido: $UUID (formato esperado: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
    fi
}

# --------------------------------------------------------------------------- #
# Gerar arquivo de configuração                                                #
# --------------------------------------------------------------------------- #
write_config() {
    local config_file="$XRAY_DIR/config.json"
    local main_inbound_tcp=""
    local main_inbound_mkcp=""

    if [[ -z "$UUID" ]]; then
        UUID="$(generate_uuid)"
        info "UUID gerado: $(c_bold "$UUID")"
    else
        validate_uuid
    fi

    # Inbound principal (porta escolhida, TCP.)
    if [[ "$PROTOCOL" == "vless" ]]; then
        main_inbound_tcp="{\"port\":${PORT},\"listen\":\"0.0.0.0\",\"protocol\":\"vless\",\"settings\":{\"clients\":[{\"id\":\"${UUID}\"}],\"decryption\":\"none\"},\"streamSettings\":{\"network\":\"tcp\",\"security\":\"none\"},\"tag\":\"inbound-vless-tcp\"}"
    else
        main_inbound_tcp="{\"port\":${PORT},\"listen\":\"0.0.0.0\",\"protocol\":\"vmess\",\"settings\":{\"clients\":[{\"id\":\"${UUID}\"}]},\"streamSettings\":{\"network\":\"tcp\",\"security\":\"none\"},\"tag\":\"inbound-vmess-tcp\"}"
    fi

    # Inbound secundário sobre mKCP (ajuda em redes que limitam TCP).
    if [[ "$PROTOCOL" == "vless" ]]; then
        main_inbound_mkcp="{\"port\":$((PORT + 1)),\"listen\":\"0.0.0.0\",\"protocol\":\"vless\",\"settings\":{\"clients\":[{\"id\":\"${UUID}\"}],\"decryption\":\"none\"},\"streamSettings\":{\"network\":\"kcp\",\"security\":\"none\",\"kcpSettings\":{\"mtu\":1350,\"tti\":50,\"uplinkCapacity\":5,\"downlinkCapacity\":20,\"congestion\":false,\"readBufferSize\":1,\"writeBufferSize\":1,\"header\":{\"type\":\"none\"}}},\"tag\":\"inbound-vless-kcp\"}"
    else
        main_inbound_mkcp="{\"port\":$((PORT + 1)),\"listen\":\"0.0.0.0\",\"protocol\":\"vmess\",\"settings\":{\"clients\":[{\"id\":\"${UUID}\"}]},\"streamSettings\":{\"network\":\"kcp\",\"security\":\"none\",\"kcpSettings\":{\"mtu\":1350,\"tti\":50,\"uplinkCapacity\":5,\"downlinkCapacity\":20,\"congestion\":false,\"readBufferSize\":1,\"writeBufferSize\":1,\"header\":{\"type\":\"none\"}}},\"tag\":\"inbound-vmess-kcp\"}"
    fi

    local routing_block=""
    if [[ -f "$XRAY_DIR/geoip.dat" ]]; then
        routing_block=$(cat <<'R'
  ,
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
R
)
    else
        warn "geoip.dat ausente — regra de blocagem de IPs privados desabilitada."
    fi

    cat > "$config_file" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "${XRAY_LOG_DIR}/access.log",
    "error": "${XRAY_LOG_DIR}/error.log"
  },
  "inbounds": [
    ${main_inbound_tcp},
    ${main_inbound_mkcp}
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ]${routing_block}
}
EOF

    chown "$XRAY_USER:$XRAY_USER" "$config_file"
    chmod 600 "$config_file"

    # Arquivos usados pelo menu de gerenciamento (xray-menu).
    if [[ ! -f "$XRAY_DIR/users.json" ]]; then
        cat > "$XRAY_DIR/users.json" <<EOF
[
  {
    "name": "default",
    "uuid": "$UUID",
    "email": "default@xray",
    "created": "$(date +%F)",
    "expiry": "",
    "limit_gb": 0,
    "suspended": false
  }
]
EOF
    fi

    if [[ ! -f "$XRAY_DIR/settings.json" ]]; then
        cat > "$XRAY_DIR/settings.json" <<EOF
{
  "protocol": "$PROTOCOL",
  "main_port": $PORT,
  "ports": [
    {"port": $PORT, "network": "tcp"},
    {"port": $((PORT + 1)), "network": "kcp"}
  ]
}
EOF
    fi

    chown "$XRAY_USER:$XRAY_USER" "$XRAY_DIR/users.json" "$XRAY_DIR/settings.json"
    chmod 600 "$XRAY_DIR/users.json" "$XRAY_DIR/settings.json"

    info "Configuração criada em $config_file"
}

# --------------------------------------------------------------------------- #
# Criar serviço systemd                                                        #
# --------------------------------------------------------------------------- #
write_systemd_service() {
    cat > "$XRAY_SERVICE" <<EOF
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
User=${XRAY_USER}
Group=${XRAY_USER}
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
AmbientCapabilities=CAP_NET_BIND_SERVICE CAP_NET_ADMIN
LimitNOFILE=65535
Restart=on-failure
RestartSec=3
ExecStart=${XRAY_BIN} run -config ${XRAY_DIR}/config.json
ExecReload=/bin/kill -HUP \$MAINPID
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1 || true
    systemctl restart xray

    info "Serviço systemd criado e habilitado ($XRAY_SERVICE)."
}

# --------------------------------------------------------------------------- #
# Testar se o serviço está rodando                                             #
# --------------------------------------------------------------------------- #
check_service() {
    sleep 2
    if ! systemctl is-active --quiet xray; then
        warn "O serviço xray não está ativo. Veja os logs com: journalctl -u xray -e"
        return 1
    fi
    info "O serviço xray está $(c_green 'ativo') e rodando."
}

# --------------------------------------------------------------------------- #
# Resumo final                                                                 #
# --------------------------------------------------------------------------- #
print_summary() {
    local ip
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    [[ -z "$ip" ]] && ip="<IP_DA_VPS>"

    printf '\n'
    info "$(c_bold 'Instalação concluída!')"
    printf '\n'
    printf '%-28s %s\n' "$(c_cyan 'IP da VPS:')" "$ip"
    printf '%-28s %s\n' "$(c_cyan 'Protocolo:')" "$PROTOCOL"
    printf '%-28s %s\n' "$(c_cyan 'Porta TCP:')" "$PORT"
    printf '%-28s %s\n' "$(c_cyan 'Porta mKCP:')" "$((PORT + 1))"
    printf '%-28s %s\n' "$(c_cyan 'UUID:')" "$(c_bold "$UUID")"
    printf '%-28s %s\n' "$(c_cyan 'Config:')" "$XRAY_DIR/config.json"
    printf '%-28s %s\n' "$(c_cyan 'Logs:')" "$XRAY_LOG_DIR/"
    printf '\n'
    info "Comandos úteis:"
    printf '  %s\n' "$(c_yellow 'sudo xray-menu')          # abrir menu de gerenciamento"
    printf '  %s\n' "$(c_yellow 'systemctl restart xray')  # reiniciar"
    printf '  %s\n' "$(c_yellow 'systemctl status xray')   # ver status"
    printf '  %s\n' "$(c_yellow 'journalctl -u xray -f')   # acompanhar logs"
    printf '  %s\n' "$(c_yellow 'bash install.sh --help')  # ver opções"
    printf '\n'
    warn "Importante: libere as portas ${PORT} e $((PORT + 1)) no firewall (ufw/iptables) e na sua operadora."
}

# --------------------------------------------------------------------------- #
# Main                                                                         #
# --------------------------------------------------------------------------- #
main() {
    parse_args "$@"
    require_root
    check_commands
    setup_user_and_dirs
    install_xray
    install_menu
    write_config
    write_systemd_service
    check_service || true
    print_summary
}

main "$@"
