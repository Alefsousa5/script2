#!/bin/bash
# ============================================================================
#  INSTALADOR COMPLETO - PAINEL SSH + XRAY
#
#  USO (1 clique na VPS):
#    bash <(curl -sL https://raw.githubusercontent.com/Alefsousa5/script2/arena/01a048cf-script2/setup.sh)
#
#  Ou após clonar o repo:
#    sudo bash setup.sh
#
#  O que faz:
#    1. Detecta SO (Debian/Ubuntu/CentOS/Alpine)
#    2. Instala todas as dependências (curl, jq, qrencode, etc.)
#    3. Baixa a última versão do painel
#    4. Instala o comando global "painel"
#    5. Opção de instalar Xray na hora
#    6. Opção de alterar porta SSH
#    7. Cria atalhos extras (painel-update, painel-uninstall)
# ============================================================================

set -e

REPO="Alefsousa5/script2"
BRANCH="arena/01a048cf-script2"
INSTALL_DIR="/opt/painel-ssh-xray"
BIN_DIR="/usr/local/bin"
VERSION="1.0.0"

# Fallback de TERM para ambientes mínimos (ex: console sem ncurses)
[ -z "$TERM" ] || [ "$TERM" = "unknown" ] || [ "$TERM" = "dumb" ] && export TERM=xterm-256color

# --------------------- helpers ---------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

print_banner() {
    clear
    echo -e "${BLUE}${BOLD}                                                            ${NC}"
    echo -e "${BLUE}${BOLD}        🚀 PAINEL SSH + XRAY - INSTALADOR v${VERSION}       ${NC}"
    echo -e "${BLUE}${BOLD}        Instalação completa para VPS                       ${NC}"
    echo -e "${BLUE}${BOLD}                                                            ${NC}"
    echo ""
}

ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${CYAN}[i]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }
err()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }

step() { echo ""; echo -e "${BOLD}${CYAN}» $*${NC}"; }

# --------------------- pré-checks ---------------------
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo "Este instalador precisa ser executado como root."
        echo "Use: sudo bash setup.sh"
        echo "Ou: sudo bash <(curl -sL URL_DO_SETUP)"
        exit 1
    fi
}

detect_os() {
    OS="$(uname -s)"
    ARCH="$(uname -m)"
    PKG=""
    INSTALL=""
    UPDATE=""

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO="$ID"
        DISTRO_FAMILIA=""
        case "$ID" in
            ubuntu|debian|linuxmint|pop|elementary|kali|raspbian|zorin)
                DISTRO_FAMILIA="debian"
                PKG="apt"
                UPDATE="apt update -y -qq"
                INSTALL="apt install -y -qq"
                ;;
            centos|rhel|fedora|rocky|almalinux|amzn|ol|virtuozzo)
                DISTRO_FAMILIA="rhel"
                PKG="yum"
                UPDATE="yum makecache -y -q || true"
                INSTALL="yum install -y -q"
                ;;
            alpine)
                DISTRO_FAMILIA="alpine"
                PKG="apk"
                UPDATE="apk update -q"
                INSTALL="apk add --no-cache -q"
                ;;
            *)
                warn "Distro '$ID' não reconhecida. Tentando apt..."
                DISTRO_FAMILIA="debian"
                PKG="apt"
                UPDATE="apt update -y -qq"
                INSTALL="apt install -y -qq"
                ;;
        esac
    else
        err "Sistema não suportado (sem /etc/os-release)."
    fi

    info "Sistema: ${BOLD}$PRETTY_NAME${NC} ($DISTRO_FAMILIA)"
    info "Arquitetura: $ARCH"
    info "Hostname: $(hostname)"
    IP_PUB=$(curl -s -m 5 https://api.ipify.org 2>/dev/null || echo "indisponível")
    info "IP Público: $IP_PUB"
}

# --------------------- instalar deps ---------------------
install_deps() {
    step "Atualizando pacotes e instalando dependências..."

    $UPDATE >/dev/null 2>&1 || true

    local pacotes="curl wget bash jq qrencode openssl net-tools iproute2 procps coreutils"
    case "$DISTRO_FAMILIA" in
        debian) pacotes="$pacotes apt-transport-https ca-certificates gnupg lsb-release" ;;
        rhel)   pacotes="$pacotes ca-certificates" ;;
    esac

    # Ferramentas úteis que não são críticas
    for p in ufw fail2ban htop iftop vnstat; do
        pacotes="$pacotes $p"
    done

    $INSTALL $pacotes 2>&1 | tail -5
    ok "Dependências instaladas."

    # Garantir sshd
    case "$DISTRO_FAMILIA" in
        debian) $INSTALL openssh-server >/dev/null 2>&1 || true ;;
        rhel)   $INSTALL openssh-server >/dev/null 2>&1 || true ;;
    esac
}

# --------------------- baixar painel ---------------------
baixar_painel() {
    step "Baixando arquivos do painel..."

    # Determinar origem: se o script está num clone local do repo, usamos local;
    # senão baixamos do GitHub.
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    mkdir -p "$INSTALL_DIR"

    if [ -f "$SCRIPT_PATH/painel.sh" ] && [ -d "$SCRIPT_PATH/modules" ]; then
        info "Copiando arquivos locais de $SCRIPT_PATH..."
        cp -f "$SCRIPT_PATH/painel.sh" "$INSTALL_DIR/"
        cp -rf "$SCRIPT_PATH/modules" "$INSTALL_DIR/"
        [ -f "$SCRIPT_PATH/uninstall.sh" ] && cp -f "$SCRIPT_PATH/uninstall.sh" "$INSTALL_DIR/"
    else
        info "Baixando do GitHub ($REPO @ $BRANCH)..."
        BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
        curl -sSL -o "$INSTALL_DIR/painel.sh" "${BASE_URL}/painel.sh"
        mkdir -p "$INSTALL_DIR/modules"
        for mod in colors.sh common.sh menu.sh ssh_manager.sh xray_manager.sh system_info.sh monitor.sh utils.sh; do
            curl -sSL -o "$INSTALL_DIR/modules/$mod" "${BASE_URL}/modules/$mod"
        done
    fi

    chmod +x "$INSTALL_DIR/painel.sh"
    ok "Arquivos instalados em $INSTALL_DIR"
}

# --------------------- criar comandos ---------------------
criar_comandos() {
    step "Criando comandos globais..."

    ln -sf "$INSTALL_DIR/painel.sh" "$BIN_DIR/painel"
    ok "Comando 'painel' criado → $BIN_DIR/painel"

    # Comando de atualização
    cat > "$BIN_DIR/painel-update" <<EOF
#!/bin/bash
if [ \$EUID -ne 0 ]; then
    echo "Execute como root: sudo painel-update"; exit 1
fi
echo "Atualizando painel..."
bash <(curl -sL https://raw.githubusercontent.com/${REPO}/${BRANCH}/setup.sh) --upgrade
EOF
    chmod +x "$BIN_DIR/painel-update"
    ok "Comando 'painel-update' criado (atualiza para última versão)"

    # Comando de desinstalação
    cat > "$BIN_DIR/painel-uninstall" <<'EOF'
#!/bin/bash
if [ $EUID -ne 0 ]; then
    echo "Execute como root: sudo painel-uninstall"; exit 1
fi
read -p "Remover completamente o painel (mantém Xray e SSH intactos)? [s/N]: " c
[ "$c" != "s" ] && [ "$c" != "S" ] && { echo "Cancelado."; exit 0; }
rm -f /usr/local/bin/painel /usr/local/bin/painel-update /usr/local/bin/painel-uninstall
rm -rf /opt/painel-ssh-xray
echo "Painel removido."
EOF
    chmod +x "$BIN_DIR/painel-uninstall"
    ok "Comando 'painel-uninstall' criado"
}

# --------------------- opções extras ---------------------
instalar_xray_opcional() {
    step "Xray"
    if command -v xray &>/dev/null || [ -f "/usr/local/bin/xray" ]; then
        ok "Xray já está instalado."
        return
    fi

    echo ""
    warn "Xray não está instalado."
    read -p "Deseja instalar o Xray agora? [S/n]: " inst_xray
    if [ "$inst_xray" != "n" ] && [ "$inst_xray" != "N" ]; then
        info "Instalando Xray via instalador oficial..."
        bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>&1 | tail -10
        if command -v xray &>/dev/null; then
            ok "Xray instalado."
            read -p "Deseja aplicar configuração BÁSICA (VLESS:443 TLS, VMess:8080, Trojan:2083)? [S/n]: " cfg_xray
            if [ "$cfg_xray" != "n" ] && [ "$cfg_xray" != "N" ]; then
                aplicar_config_basica_xray
            fi
        else
            warn "Falha na instalação do Xray. Você pode instalar depois pelo painel."
        fi
    else
        info "Você pode instalar o Xray depois pelo painel (menu Xray → opção 2)."
    fi
}

aplicar_config_basica_xray() {
    XRAY_DIR="/usr/local/etc/xray"
    XRAY_CONFIG="$XRAY_DIR/config.json"
    mkdir -p "$XRAY_DIR"
    mkdir -p /var/log/xray

    [ -f "$XRAY_CONFIG" ] && cp "$XRAY_CONFIG" "${XRAY_CONFIG}.before-painel-$(date +%Y%m%d%H%M%S).json"

    # Portas
    read -p "Porta VLESS [443]: " port_vless; port_vless="${port_vless:-443}"
    read -p "Porta VMess [8080]: " port_vmess; port_vmess="${port_vmess:-8080}"
    read -p "Porta Trojan [2083]: " port_trojan; port_trojan="${port_trojan:-2083}"

    # Certificado
    CERT_FILE="$XRAY_DIR/server.crt"
    KEY_FILE="$XRAY_DIR/server.key"
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        info "Gerando certificado TLS auto-assinado..."
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -keyout "$KEY_FILE" -out "$CERT_FILE" \
            -subj "/C=BR/ST=RJ/L=Rio/O=Painel/CN=example.com" >/dev/null 2>&1
        ok "Certificado gerado."
    fi

    cat > "$XRAY_CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
    {
      "port": $port_vless,
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{"certificateFile": "$CERT_FILE", "keyFile": "$KEY_FILE"}]
        }
      },
      "tag": "vless-in",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "port": $port_vmess,
      "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {"network": "tcp"},
      "tag": "vmess-in",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "port": $port_trojan,
      "protocol": "trojan",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{"certificateFile": "$CERT_FILE", "keyFile": "$KEY_FILE"}]
        }
      },
      "tag": "trojan-in",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
  ],
  "outbounds": [
    {"protocol": "freedom", "settings": {}, "tag": "direct"},
    {"protocol": "blackhole", "settings": {}, "tag": "block"}
  ],
  "routing": {"domainStrategy": "AsIs", "rules": []}
}
EOF

    systemctl enable xray >/dev/null 2>&1
    if systemctl restart xray; then
        ok "Configuração aplicada e Xray iniciado!"
        info "Portas: VLESS=$port_vless  VMess=$port_vmess  Trojan=$port_trojan"
        info "Lembre-se de liberar essas portas no firewall."
    else
        err "Xray não conseguiu iniciar. Verifique os logs com: journalctl -u xray"
    fi
}

abrir_portas_firewall() {
    step "Firewall"
    if command -v ufw &>/dev/null; then
        if ufw status 2>/dev/null | grep -q "inactive"; then
            warn "UFW está instalado mas INATIVO."
            read -p "Deseja ativar o UFW e liberar SSH + Xray? [s/N]: " ativ
            if [ "$ativ" = "s" ] || [ "$ativ" = "S" ]; then
                local ssh_port
                ssh_port=$(grep -E "^Port\s+" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')
                ssh_port="${ssh_port:-22}"
                ufw allow "$ssh_port/tcp" >/dev/null 2>&1
                for p in $port_vless $port_vmess $port_trojan; do
                    ufw allow "$p/tcp" >/dev/null 2>&1
                    ufw allow "$p/udp" >/dev/null 2>&1
                done
                ufw --force enable >/dev/null 2>&1
                ok "Firewall ativado."
            fi
        else
            info "UFW está ativo. Liberando portas necessárias..."
            for p in ${port_vless:-443} ${port_vmess:-8080} ${port_trojan:-2083}; do
                ufw allow "$p/tcp" >/dev/null 2>&1
            done
            ok "Portas liberadas no UFW."
        fi
    else
        info "UFW não instalado. Recomenda-se: apt install ufw"
    fi
}

# --------------------- upgrade mode ---------------------
if [ "$1" = "--upgrade" ]; then
    echo "Atualizando painel..."
    check_root
    detect_os
    mkdir -p "$INSTALL_DIR"
    BASE_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
    curl -sSL -o "$INSTALL_DIR/painel.sh" "${BASE_URL}/painel.sh"
    mkdir -p "$INSTALL_DIR/modules"
    for mod in colors.sh common.sh menu.sh ssh_manager.sh xray_manager.sh system_info.sh monitor.sh utils.sh; do
        curl -sSL -o "$INSTALL_DIR/modules/$mod" "${BASE_URL}/modules/$mod"
    done
    chmod +x "$INSTALL_DIR/painel.sh"
    echo "Painel atualizado para a versão $VERSION."
    exit 0
fi

# --------------------- fluxo principal ---------------------
print_banner
check_root
detect_os
install_deps
baixar_painel
criar_comandos
instalar_xray_opcional
abrir_portas_firewall

# --------------------- resumo final ---------------------
echo ""
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  ✅ INSTALAÇÃO CONCLUÍDA COM SUCESSO!${NC}"
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Comandos disponíveis:${NC}"
echo -e "    ${CYAN}painel${NC}             - Abre o painel"
echo -e "    ${CYAN}painel-update${NC}      - Atualiza o painel"
echo -e "    ${CYAN}painel-uninstall${NC}   - Remove o painel"
echo ""
echo -e "  ${BOLD}Para abrir agora:${NC}"
echo -e "    ${GREEN}sudo painel${NC}"
echo ""
echo -e "  ${BOLD}Diretório de instalação:${NC} $INSTALL_DIR"
echo -e "  ${BOLD}IP da VPS:${NC} $IP_PUB"
echo ""
echo -e "${YELLOW}  Recomendações:${NC}"
echo -e "    1. Rode ${GREEN}sudo painel${NC} e acesse o menu Xray para criar contas"
echo -e "    2. Altere a porta SSH no menu SSH → opção 6"
echo -e "    3. Desabilite login root por senha em SSH → opção 8"
echo -e "    4. Configure o fail2ban se não estiver rodando"
echo ""
echo -e "${BLUE}${BOLD}══════════════════════════════════════════════════════════${NC}"

# Abrir painel na hora?
read -p "Deseja abrir o painel agora? [S/n]: " open_now
if [ "$open_now" != "n" ] && [ "$open_now" != "N" ]; then
    exec painel
fi
