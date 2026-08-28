# ============================================================================
# FUNÇÕES COMUNS - Utilitários gerais do painel
# ============================================================================

# Caminhos importantes
XRAY_DIR="/usr/local/etc/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"
XRAY_SERVICE="xray"
SSH_CONFIG="/etc/ssh/sshd_config"
PAINEL_LOG="$SCRIPT_DIR/painel.log"

# Limpeza de tela + espera
pause() {
    echo ""
    echo -e "${YELLOW}Pressione ENTER para continuar...${RESET}"
    read -r
}

# Linha separadora
linha() {
    echo -e "${CYAN}==========================================================${RESET}"
}

linha_dupla() {
    echo -e "${MAGENTA}══════════════════════════════════════════════════════════${RESET}"
}

# Ler entrada com valor default
ler_input() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local resposta
    if [ -n "$default" ]; then
        echo -ne "${CYAN}$prompt${RESET} [${GREEN}$default${RESET}]: "
    else
        echo -ne "${CYAN}$prompt${RESET}: "
    fi
    read -r resposta
    if [ -z "$resposta" ] && [ -n "$default" ]; then
        resposta="$default"
    fi
    eval "$varname=\"\$resposta\""
}

# Gerar UUID
gerar_uuid() {
    if command -v xray &>/dev/null; then
        xray uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid
    else
        cat /proc/sys/kernel/random/uuid
    fi
}

# Obter IP público
get_ip_publico() {
    local ip
    ip=$(curl -s -m 5 https://api.ipify.org 2>/dev/null || \
         curl -s -m 5 https://ifconfig.me 2>/dev/null || \
         curl -s -m 5 https://icanhazip.com 2>/dev/null)
    echo "${ip:-127.0.0.1}"
}

# Obter IP público IPv6
get_ip6_publico() {
    curl -s -m 5 https://api64.ipify.org 2>/dev/null || echo ""
}

# Validar porta livre
porta_livre() {
    local porta="$1"
    ! ss -tuln 2>/dev/null | grep -qE ":$porta\s" && \
    ! netstat -tuln 2>/dev/null | grep -qE ":$porta\s"
}

# Banner principal
banner_init() {
    clear
    echo -e "${BG_BLUE}${BOLD}${WHITE}                                                            ${RESET}"
    echo -e "${BG_BLUE}${BOLD}${WHITE}        🚀 PAINEL SSH + XRAY - VPS MANAGER v1.0            ${RESET}"
    echo -e "${BG_BLUE}${BOLD}${WHITE}        Gerenciamento completo via script                  ${RESET}"
    echo -e "${BG_BLUE}${BOLD}${WHITE}                                                            ${RESET}"
    echo ""
}

# Verificar se Xray está instalado
XRAY_INSTALADO=0
checar_xray_instalado() {
    if [ -f "/usr/local/bin/xray" ] || command -v xray &>/dev/null; then
        XRAY_INSTALADO=1
    fi
}

# Checar dependências básicas
checar_dependencias() {
    local faltando=()
    for cmd in curl wget ss netstat openssl qrencode jq; do
        if ! command -v "$cmd" &>/dev/null; then
            faltando+=("$cmd")
        fi
    done
    # ssh é o cliente e sshd o servidor — sempre tem openssh-server para ter sshd_config
    if ! command -v sshd &>/dev/null && ! dpkg -l openssh-server 2>/dev/null | grep -q '^ii' 2>/dev/null; then
        faltando+=("openssh-server")
    fi

    # netstat pode estar em net-tools
    if ! command -v netstat &>/dev/null; then
        if ! dpkg -l net-tools 2>/dev/null | grep -q '^ii' 2>/dev/null; then
            faltando+=("net-tools")
        fi
    fi

    if [ ${#faltando[@]} -gt 0 ]; then
        echo -e "${YELLOW}[!] Instalando dependências: ${faltando[*]}${RESET}"
        if command -v apt &>/dev/null; then
            apt update -qq && apt install -y -qq "${faltando[@]}" curl wget openssh-server openssl jq qrencode net-tools >/dev/null 2>&1
        elif command -v yum &>/dev/null; then
            yum install -y -q "${faltando[@]}" curl wget openssh-server openssl jq qrencode net-tools >/dev/null 2>&1
        fi
        sucesso "Dependências instaladas."
    fi
}

# Gerar senha aleatória
gerar_senha() {
    local tamanho="${1:-12}"
    tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom | head -c "$tamanho"
    echo
}
