#!/bin/bash

# ==============================================================================
# VPS MANAGER PRO - Painel de Gerenciamento de Servidor
# Compatível com Ubuntu / Debian
# Edit/Automação: Arena - fork Alefsousa5/script2
# ==============================================================================

# Cores e Estilos
NC='\033[0m'
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'

# Repo de origem (para instalar atalho e atualizar)
_ref="${SCRIPT2_REF:-main}"
SCRIPT_URL="https://raw.githubusercontent.com/Alefsousa5/script2/${_ref}/vpsmanager.sh"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
VPS_DIR="/usr/local/lib/vpsmanager"

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERRO] Este script precisa ser executado como root!${NC}"
    echo -e "${YELLOW}Use: sudo ./vpsmanager.sh ou su -${NC}"
    exit 1
fi

# Log de ações
LOG_FILE="/var/log/vps_manager.log"
log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Detecção de Sistema Operacional
detectar_sistema() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        OS=$(uname -s)
        VER=$(uname -r)
    fi

    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        echo -e "${YELLOW}[AVISO] Este script foi otimizado para Ubuntu e Debian.${NC}"
    fi
}
detectar_sistema

# Instalar dependências básicas se necessário
verificar_dependencias() {
    local deps=("curl" "wget" "bc" "ufw" "net-tools" "jq" "netcat-openbsd")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            apt-get update -qq &> /dev/null
            apt-get install -y "$dep" &> /dev/null
        fi
    done
}
verificar_dependencias

# Função de pausa
pausa() {
    echo -e ""
    read -p "Pressione [Enter] para retornar ao menu..."
}

# ==============================================================================
# UTILITÁRIOS DE PORTA / XRAY
# ==============================================================================
port_in_use() {
    netstat -tunlp 2>/dev/null | awk -v p=":$1$" '$4 ~ p {found=1} END {exit !found}'
}
port_owner() {
    netstat -tunlp 2>/dev/null | awk -v p=":$1$" '$4 ~ p {print $7}' | head -1
}
liberar_porta() {
    local _pid=$(netstat -tunlp 2>/dev/null | awk -v p=":$1$" '$4 ~ p {print $7}' | head -1 | cut -d'/' -f1)
    [[ -n "$_pid" ]] && kill "$_pid" > /dev/null 2>&1 && sleep 2
}
xray_service_fix() {
    [[ ! -d /etc/systemd/system/xray.service.d ]] && mkdir -p /etc/systemd/system/xray.service.d
    cat > /etc/systemd/system/xray.service.d/10-bind.conf <<'EOF'
[Service]
User=root
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
EOF
    systemctl daemon-reload > /dev/null 2>&1
}
xray_base_config() {
    local _port="$1" _proto="${2:-vless}" _path="${3:-/vpsmanager}"
    [[ ! -d /usr/local/etc/xray ]] && mkdir -p /usr/local/etc/xray
    if [[ "$_proto" = "vmess" ]]; then
        local _settings='"settings": { "clients": [] }'
    else
        local _settings='"settings": { "decryption": "none", "clients": [] }'
    fi
    cat > "$XRAY_CONFIG" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "inbound-vpsmanager",
      "listen": "0.0.0.0",
      "port": ${_port},
      "protocol": "${_proto}",
      ${_settings},
      "streamSettings": {
        "network": "ws",
        "security": "none",
        "wsSettings": { "path": "${_path}" }
      }
    }
  ],
  "outbounds": [ { "protocol": "freedom", "tag": "direct" } ]
}
EOF
}
xray_online() {
    systemctl is-active --quiet xray 2>/dev/null && return 0
    netstat -tunlp 2>/dev/null | grep -w xray > /dev/null 2>&1
}
xray_ip() {
    curl -s4 ifconfig.me 2>/dev/null || curl -s4 ipv4.icanhazip.com 2>/dev/null
}
xray_info() {
    XR_IP=$(xray_ip)
    XR_PORT=$(jq -r '.inbounds[0].port' "$XRAY_CONFIG" 2>/dev/null)
    XR_PROTO=$(jq -r '.inbounds[0].protocol' "$XRAY_CONFIG" 2>/dev/null)
    XR_PATH=$(jq -r '.inbounds[0].streamSettings.wsSettings.path' "$XRAY_CONFIG" 2>/dev/null)
}
xray_gen_link() { # $1=uuid $2=nome
    local _enc_path=$(echo "$XR_PATH" | sed 's|/|%2F|g')
    if [[ "$XR_PROTO" = "vmess" ]]; then
        local _j="{\"v\":\"2\",\"ps\":\"$2\",\"add\":\"$XR_IP\",\"port\":\"$XR_PORT\",\"id\":\"$1\",\"aid\":\"0\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"$XR_IP\",\"path\":\"$XR_PATH\",\"tls\":\"\"}"
        echo "vmess://$(echo -n "$_j" | base64 -w 0)"
    else
        echo "vless://$1@$XR_IP:$XR_PORT?type=ws&security=none&path=${_enc_path}#$2"
    fi
}

# ==============================================================================
# SUBMENUS E FUNÇÕES
# ==============================================================================

# 01 — Usuários SSH
menu_ssh() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}           01 — GERENCIAR USUÁRIOS SSH        ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Criar usuário                         ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Excluir usuário                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Alterar senha                         ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[04]${NC} Bloquear / Desbloquear                ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[05]${NC} Definir validade                      ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[06]${NC} Limitar processos                     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[07]${NC} Ver usuários conectados               ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[08]${NC} Derrubar conexão                      ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[09]${NC} Listar usuários                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_ssh

        case $op_ssh in
            1|01)
                echo -e "\n${BLUE}=== Criar Usuário SSH ===${NC}"
                read -p "Nome do usuário: " new_user
                if [[ -z "$new_user" ]]; then
                    echo -e "${RED}Nome inválido!${NC}"
                elif id "$new_user" &>/dev/null; then
                    echo -e "${RED}Usuário já existe!${NC}"
                else
                    read -s -p "Senha para o usuário: " new_pass; echo ""
                    read -p "Validade em dias (vazio = sem expiração): " new_days
                    useradd -m -s /bin/bash "$new_user"
                    echo "$new_user:$new_pass" | chpasswd
                    [[ "$new_days" =~ ^[0-9]+$ ]] && chage -E "$(date -d "+$new_days days" +%Y-%m-%d)" "$new_user"
                    echo -e "${GREEN}Usuário $new_user criado com sucesso!${NC}"
                    log_action "Criou usuário SSH: $new_user"
                fi
                pausa
                ;;
            2|02)
                echo -e "\n${BLUE}=== Excluir Usuário SSH ===${NC}"
                read -p "Nome do usuário a excluir: " del_user
                if id "$del_user" &>/dev/null; then
                    read -p "Tem certeza que deseja apagar $del_user e seus arquivos? (s/n): " confirm
                    if [[ "$confirm" =~ ^[sS]$ ]]; then
                        pkill -u "$del_user" 2>/dev/null
                        userdel -r "$del_user" 2>/dev/null
                        echo -e "${GREEN}Usuário $del_user removido.${NC}"
                        log_action "Removeu usuário SSH: $del_user"
                    fi
                else
                    echo -e "${RED}Usuário não encontrado!${NC}"
                fi
                pausa
                ;;
            3|03)
                echo -e "\n${BLUE}=== Alterar Senha ===${NC}"
                read -p "Nome do usuário: " alt_user
                if id "$alt_user" &>/dev/null; then
                    read -s -p "Nova senha: " alt_pass; echo ""
                    echo "$alt_user:$alt_pass" | chpasswd
                    echo -e "${GREEN}Senha alterada com sucesso!${NC}"
                    log_action "Alterou senha do usuário: $alt_user"
                else
                    echo -e "${RED}Usuário não encontrado!${NC}"
                fi
                pausa
                ;;
            4|04)
                echo -e "\n${BLUE}=== Bloquear / Desbloquear Usuário ===${NC}"
                read -p "Nome do usuário: " lock_user
                if id "$lock_user" &>/dev/null; then
                    echo -e "1) Bloquear\n2) Desbloquear"
                    read -p "Escolha: " lck_opt
                    if [ "$lck_opt" = "1" ]; then
                        passwd -l "$lock_user"
                        usermod -s /usr/sbin/nologin "$lock_user"
                        echo -e "${YELLOW}Usuário bloqueado.${NC}"
                        log_action "Bloqueou usuário: $lock_user"
                    else
                        passwd -u "$lock_user"
                        usermod -s /bin/bash "$lock_user"
                        echo -e "${GREEN}Usuário desbloqueado.${NC}"
                        log_action "Desbloqueou usuário: $lock_user"
                    fi
                else
                    echo -e "${RED}Usuário não encontrado!${NC}"
                fi
                pausa
                ;;
            5|05)
                echo -e "\n${BLUE}=== Definir Validade ===${NC}"
                read -p "Nome do usuário: " val_user
                read -p "Data de expiração (AAAA-MM-DD): " val_date
                if id "$val_user" &>/dev/null; then
                    chage -E "$val_date" "$val_user"
                    echo -e "${GREEN}Validade definida para $val_date.${NC}"
                    log_action "Definiu validade para $val_user até $val_date"
                else
                    echo -e "${RED}Usuário não encontrado!${NC}"
                fi
                pausa
                ;;
            6|06)
                echo -e "\n${BLUE}=== Limitar Processos ===${NC}"
                read -p "Nome do usuário: " lim_user
                read -p "Máximo de processos (ex: 30): " lim_proc
                if id "$lim_user" &>/dev/null; then
                    if [[ "$lim_proc" =~ ^[0-9]+$ ]]; then
                        if grep -q "^$lim_user .*nproc" /etc/security/limits.conf; then
                            sed -i "/^$lim_user .*nproc/d" /etc/security/limits.conf
                        fi
                        echo "$lim_user hard nproc $lim_proc" >> /etc/security/limits.conf
                        echo "$lim_user soft nproc $lim_proc" >> /etc/security/limits.conf
                        echo -e "${GREEN}Limite de processos configurado para $lim_user.${NC}"
                        log_action "Limitou processos de $lim_user para $lim_proc"
                    else
                        echo -e "${RED}Valor inválido! Use apenas números.${NC}"
                    fi
                else
                    echo -e "${RED}Usuário não encontrado!${NC}"
                fi
                pausa
                ;;
            7|07)
                echo -e "\n${BLUE}=== Usuários Conectados ===${NC}"
                who
                pausa
                ;;
            8|08)
                echo -e "\n${BLUE}=== Derrubar Conexão (Kill) ===${NC}"
                read -p "Digite o nome do usuário para derrubar sessões: " kill_user
                pkill -u "$kill_user"
                echo -e "${GREEN}Sessões de $kill_user encerradas.${NC}"
                log_action "Derrubou sessões do usuário: $kill_user"
                pausa
                ;;
            9|09)
                echo -e "\n${BLUE}=== Listar Usuários do Sistema ===${NC}"
                awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd
                pausa
                ;;
            0|00)
                break
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                sleep 1
                ;;
        esac
    done
}

# 02 — Senhas / Acessos
menu_senhas() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}              02 — SENHAS / ACESSOS           ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Alterar senha do Root                ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Configurar Chaves SSH (Authorized_keys)${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Ativar/Desativar Login por Senha     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_senhas

        case $op_senhas in
            1|01)
                echo -e "\n${BLUE}=== Alterar Senha do Root ===${NC}"
                passwd root
                log_action "Alterou a senha do root"
                pausa
                ;;
            2|02)
                echo -e "\n${BLUE}=== Configurar Chaves SSH ===${NC}"
                mkdir -p ~/.ssh
                echo -e "${YELLOW}Cole sua chave pública SSH abaixo:${NC}"
                read -p "Chave: " pub_key
                if [[ -n "$pub_key" ]]; then
                    echo "$pub_key" >> ~/.ssh/authorized_keys
                    chmod 600 ~/.ssh/authorized_keys
                    chmod 700 ~/.ssh
                    echo -e "${GREEN}Chave adicionada com sucesso!${NC}"
                    log_action "Adicionou chave pública SSH"
                else
                    echo -e "${RED}Chave vazia!${NC}"
                fi
                pausa
                ;;
            3|03)
                echo -e "\n${BLUE}=== Configurar Login por Senha no SSH ===${NC}"
                echo -e "1) Permitir Login por Senha\n2) Bloquear Login por Senha (Apenas Chaves)"
                read -p "Escolha: " s_opt
                if [ "$s_opt" = "1" ]; then
                    if grep -qE "^#?PasswordAuthentication" /etc/ssh/sshd_config; then
                        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
                    else
                        echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
                    fi
                else
                    if grep -qE "^#?PasswordAuthentication" /etc/ssh/sshd_config; then
                        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
                    else
                        echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
                    fi
                fi
                systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
                echo -e "${GREEN}Configuração aplicada e SSH reiniciado!${NC}"
                log_action "Alterou PasswordAuthentication do SSH (opcao $s_opt)"
                pausa
                ;;
            0|00)
                break
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                sleep 1
                ;;
        esac
    done
}

# 03 — Xray / V2Ray
menu_xray() {
    while true; do
        clear
        local _sts _sts_txt _sts_cor
        if xray_online; then _sts_txt="ATIVO"; _sts_cor="$GREEN"; else _sts_txt="PARADO/NAO INSTALADO"; _sts_cor="$RED"; fi
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}              03 — XRAY / V2RAY               ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        printf "${CYAN}║${NC}  STATUS: ${_sts_cor}%-36s${CYAN}║${NC}\n" "$_sts_txt"
        if [[ -f "$XRAY_CONFIG" ]]; then
            xray_info
            _cfgline=$(echo "$XR_PROTO | PORTA: $XR_PORT | PATH: $XR_PATH" | cut -c1-44)
            printf "${CYAN}║${NC}  ${YELLOW}%-44s${CYAN}║${NC}\n" "$_cfgline"
        fi
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Instalar Xray                         ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Remover Xray                          ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Iniciar / Parar / Reiniciar           ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[04]${NC} Ver status                            ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[05]${NC} Editar configuração                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[06]${NC} Gerenciar clientes                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[07]${NC} Gerar configurações                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[08]${NC} Ver logs                              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[09]${NC} Testar portas                         ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_xray

        case $op_xray in
            1|01)
                echo -e "\n${BLUE}=== Instalar Xray ===${NC}"
                if command -v xray &>/dev/null || [[ -x /usr/local/bin/xray ]]; then
                    read -p "Xray já instalado. Reinstalar configuração? (s/n): " re_x
                    [[ "$re_x" =~ ^[sS]$ ]] || { pausa; continue; }
                fi
                while true; do
                    read -p "Porta WebSocket [80]: " x_port
                    x_port="${x_port:-80}"
                    [[ "$x_port" =~ ^[0-9]+$ && "$x_port" -le 65535 ]] || { echo -e "${RED}Porta inválida!${NC}"; continue; }
                    if port_in_use "$x_port"; then
                        echo -e "${YELLOW}Porta $x_port em uso por: $(port_owner "$x_port")${NC}"
                        read -p "Liberar a porta e continuar? (s/n): " _lib
                        if [[ "$_lib" =~ ^[sS]$ ]]; then
                            liberar_porta "$x_port"
                            port_in_use "$x_port" && { echo -e "${RED}Não foi possível liberar!${NC}"; continue; }
                        else
                            continue
                        fi
                    fi
                    break
                done
                read -p "Caminho WebSocket [/vpsmanager]: " x_path
                x_path="${x_path:-/vpsmanager}"
                [[ "${x_path:0:1}" != "/" ]] && x_path="/$x_path"
                echo -e "1) VLESS (recomendado)\n2) VMESS"
                read -p "Protocolo [1]: " x_prot
                [[ "$x_prot" = "2" ]] && x_proto="vmess" || x_proto="vless"
                echo -e "${YELLOW}Instalando dependências...${NC}"
                apt-get update -qq > /dev/null 2>&1
                apt-get install -y curl wget unzip jq -qq > /dev/null 2>&1
                echo -e "${YELLOW}Baixando e instalando Xray-core...${NC}"
                bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install > /dev/null 2>&1
                if [[ ! -x /usr/local/bin/xray ]]; then
                    echo -e "${RED}Falha ao instalar o Xray! Verifique a conexão.${NC}"
                    pausa
                    continue
                fi
                xray_base_config "$x_port" "$x_proto" "$x_path"
                xray_service_fix
                systemctl enable xray > /dev/null 2>&1
                systemctl restart xray 2>/dev/null || service xray restart 2>/dev/null
                [[ -f "/usr/sbin/ufw" ]] && ufw allow "$x_port"/tcp > /dev/null 2>&1
                echo ""
                if xray_online; then
                    echo -e "${GREEN}✔ Xray instalado e ATIVO!${NC}"
                    echo -e "${GREEN}  Protocolo: $x_proto | Porta: $x_port | Path: $x_path${NC}"
                    echo -e "${YELLOW}  Use a opção [06] para adicionar clientes (UUID).${NC}"
                    log_action "Instalou Xray ($x_proto, porta $x_port, path $x_path)"
                else
                    echo -e "${RED}Xray instalado, mas o serviço não subiu. Últimos logs:${NC}"
                    journalctl -u xray -n 12 --no-pager 2>/dev/null
                fi
                pausa
                ;;
            2|02)
                read -p "Deseja realmente desinstalar o Xray? (s/n): " conf_x
                if [[ "$conf_x" =~ ^[sS]$ ]]; then
                    bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge > /dev/null 2>&1
                    rm -rf /etc/systemd/system/xray.service.d /usr/local/etc/xray > /dev/null 2>&1
                    systemctl daemon-reload > /dev/null 2>&1
                    echo -e "${GREEN}Xray removido.${NC}"
                    log_action "Removeu o Xray"
                fi
                pausa
                ;;
            3|03)
                echo -e "1) Iniciar\n2) Parar\n3) Reiniciar"
                read -p "Escolha: " x_act
                case $x_act in
                    1) systemctl start xray ;;
                    2) systemctl stop xray ;;
                    3) xray_service_fix; systemctl restart xray ;;
                esac
                sleep 1
                xray_online && echo -e "${GREEN}Xray ATIVO!${NC}" || echo -e "${YELLOW}Xray PARADO.${NC}"
                pausa
                ;;
            4|04)
                systemctl status xray --no-pager
                pausa
                ;;
            5|05)
                if [ -f "$XRAY_CONFIG" ]; then
                    nano "$XRAY_CONFIG"
                    if /usr/local/bin/xray run -test -config "$XRAY_CONFIG" > /dev/null 2>&1 || /usr/local/bin/xray -test -config "$XRAY_CONFIG" > /dev/null 2>&1; then
                        systemctl restart xray
                        echo -e "${GREEN}Configuração válida! Xray reiniciado.${NC}"
                    else
                        echo -e "${RED}ATENÇÃO: configuração com erro de sintaxe! Verifique antes de reiniciar.${NC}"
                    fi
                else
                    echo -e "${RED}Arquivo de configuração não encontrado!${NC}"
                fi
                pausa
                ;;
            6|06)
                menu_xray_clientes
                ;;
            7|07)
                if [[ ! -f "$XRAY_CONFIG" ]]; then
                    echo -e "${RED}Xray não configurado! Instale primeiro (opção 01).${NC}"
                    pausa
                    continue
                fi
                xray_info
                echo -e "\n${BLUE}=== Links de Configuração ===${NC}"
                echo -e "${YELLOW}Servidor:${NC} $XR_IP  ${YELLOW}Porta:${NC} $XR_PORT  ${YELLOW}Proto:${NC} $XR_PROTO  ${YELLOW}Path:${NC} $XR_PATH"
                echo -e "${CYAN}──────────────────────────────────────────────${NC}"
                _tcli=$(jq -r '.inbounds[0].settings.clients | length' "$XRAY_CONFIG" 2>/dev/null)
                if [[ "$_tcli" = "0" ]]; then
                    echo -e "${RED}Nenhum cliente cadastrado! Use a opção [06].${NC}"
                else
                    jq -r '.inbounds[0].settings.clients[] | .id + "|" + .email' "$XRAY_CONFIG" | while IFS='|' read -r _id _em; do
                        _nick="${_em%@*}"
                        echo -e "${GREEN}► $_nick${NC}"
                        xray_gen_link "$_id" "$_nick"
                        echo -e "${CYAN}──────────────────────────────────────────────${NC}"
                    done
                fi
                pausa
                ;;
            8|08)
                journalctl -u xray -n 50 --no-pager
                pausa
                ;;
            9|09)
                read -p "Digite a porta para testar: " t_porta
                nc -zv 127.0.0.1 "$t_porta" || echo -e "${RED}Porta fechada ou inacessível.${NC}"
                pausa
                ;;
            0|00)
                break
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                sleep 1
                ;;
        esac
    done
}

# 03.6 — Clientes Xray
menu_xray_clientes() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}           03.6 — CLIENTES XRAY               ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Listar clientes                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Adicionar cliente (UUID)              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Remover cliente                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar                                ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_cli

        case $op_cli in
            1|01)
                echo -e "\n${BLUE}=== Clientes Xray ===${NC}"
                if [[ -f "$XRAY_CONFIG" ]]; then
                    _n=0
                    jq -r '.inbounds[0].settings.clients[] | .id + "|" + .email' "$XRAY_CONFIG" 2>/dev/null | while IFS='|' read -r _id _em; do
                        _n=$((_n+1))
                        echo -e "  ${YELLOW}[$_n]${NC} ${_em%@*} ${CYAN}$_id${NC}"
                    done
                    [[ "$(jq -r '.inbounds[0].settings.clients | length' "$XRAY_CONFIG" 2>/dev/null)" = "0" ]] && echo -e "${RED}Nenhum cliente cadastrado.${NC}"
                else
                    echo -e "${RED}Xray não configurado!${NC}"
                fi
                pausa
                ;;
            2|02)
                if [[ ! -f "$XRAY_CONFIG" ]]; then
                    echo -e "${RED}Instale o Xray primeiro (opção 01).${NC}"
                    pausa
                    continue
                fi
                echo -e "\n${BLUE}=== Adicionar Cliente ===${NC}"
                read -p "Nome/identificação do cliente: " cli_nome
                [[ -z "$cli_nome" ]] && { echo -e "${RED}Nome inválido!${NC}"; pausa; continue; }
                cli_nome=$(echo "$cli_nome" | tr -dc 'a-zA-Z0-9_-')
                cli_uuid=$(cat /proc/sys/kernel/random/uuid)
                jq --arg id "$cli_uuid" --arg email "$cli_nome@vps" \
                   '.inbounds[0].settings.clients += [{"id": $id, "email": $email}]' \
                   "$XRAY_CONFIG" > /tmp/xray_cli.json && mv /tmp/xray_cli.json "$XRAY_CONFIG"
                systemctl restart xray
                xray_info
                echo -e "${GREEN}✔ Cliente adicionado!${NC}"
                echo -e "  ${YELLOW}Nome:${NC} $cli_nome"
                echo -e "  ${YELLOW}UUID:${NC} $cli_uuid"
                echo -e "  ${YELLOW}Link:${NC}"
                xray_gen_link "$cli_uuid" "$cli_nome"
                log_action "Adicionou cliente Xray: $cli_nome ($cli_uuid)"
                pausa
                ;;
            3|03)
                if [[ ! -f "$XRAY_CONFIG" ]]; then
                    echo -e "${RED}Xray não configurado!${NC}"
                    pausa
                    continue
                fi
                echo -e "\n${BLUE}=== Remover Cliente ===${NC}"
                jq -r '.inbounds[0].settings.clients[] | .id + "|" + .email' "$XRAY_CONFIG" 2>/dev/null | cat -n
                [[ "$(jq -r '.inbounds[0].settings.clients | length' "$XRAY_CONFIG" 2>/dev/null)" = "0" ]] && { echo -e "${RED}Nenhum cliente.${NC}"; pausa; continue; }
                read -p "Número do cliente (ou UUID): " cli_del
                if [[ "$cli_del" =~ ^[0-9]+$ && "${#cli_del}" -le 3 ]]; then
                    cli_del=$(jq -r ".inbounds[0].settings.clients[$((cli_del-1))].id" "$XRAY_CONFIG" 2>/dev/null)
                fi
                [[ "$cli_del" = "null" || -z "$cli_del" ]] && { echo -e "${RED}Cliente inválido!${NC}"; pausa; continue; }
                jq --arg id "$cli_del" '.inbounds[0].settings.clients |= map(select(.id != $id))' \
                   "$XRAY_CONFIG" > /tmp/xray_cli.json && mv /tmp/xray_cli.json "$XRAY_CONFIG"
                systemctl restart xray
                echo -e "${GREEN}Cliente removido!${NC}"
                log_action "Removeu cliente Xray: $cli_del"
                pausa
                ;;
            0|00)
                break
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                sleep 1
                ;;
        esac
    done
}

# 04 — Serviços do Servidor
menu_servicos() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}           04 — SERVIÇOS DO SERVIDOR          ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} SSH                                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Nginx                                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Apache                                ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[04]${NC} Docker                                ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[05]${NC} Xray                                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[06]${NC} Cron                                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[07]${NC} Reiniciar serviços                    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[08]${NC} Ver serviços ativos                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_serv

        case $op_serv in
            1|01) systemctl restart ssh 2>/dev/null || systemctl restart sshd; echo -e "${GREEN}SSH Reiniciado!${NC}"; pausa ;;
            2|02) systemctl restart nginx; echo -e "${GREEN}Nginx Reiniciado!${NC}"; pausa ;;
            3|03) systemctl restart apache2; echo -e "${GREEN}Apache Reiniciado!${NC}"; pausa ;;
            4|04) systemctl restart docker; echo -e "${GREEN}Docker Reiniciado!${NC}"; pausa ;;
            5|05) systemctl restart xray; echo -e "${GREEN}Xray Reiniciado!${NC}"; pausa ;;
            6|06) systemctl restart cron; echo -e "${GREEN}Cron Reiniciado!${NC}"; pausa ;;
            7|07)
                for s in ssh nginx apache2 docker xray cron; do
                    systemctl restart "$s" 2>/dev/null && echo -e "  ${GREEN}✔ $s${NC}" || echo -e "  ${YELLOW}- $s (ausente/falhou)${NC}"
                done
                echo -e "${GREEN}Principais serviços verificados!${NC}"
                pausa
                ;;
            8|08)
                systemctl list-units --type=service --state=running --no-pager
                pausa
                ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# 05 — Firewall / Portas
menu_firewall() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}            05 — FIREWALL / PORTAS            ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Abrir porta                           ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Fechar porta                          ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Listar portas                         ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[04]${NC} UFW (Ativar / Desativar / Status)     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[05]${NC} Regras básicas                        ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[06]${NC} Ver conexões                          ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_fw

        case $op_fw in
            1|01)
                read -p "Digite a porta para abrir (ex: 8080 ou 8080/tcp): " p_abrir
                ufw allow "$p_abrir"
                echo -e "${GREEN}Porta $p_abrir aberta no firewall!${NC}"
                log_action "Abriu porta $p_abrir no firewall"
                pausa
                ;;
            2|02)
                read -p "Digite a porta para fechar: " p_fechar
                ufw deny "$p_fechar"
                echo -e "${YELLOW}Porta $p_fechar bloqueada!${NC}"
                log_action "Fechou porta $p_fechar no firewall"
                pausa
                ;;
            3|03)
                ufw status numbered
                pausa
                ;;
            4|04)
                echo -e "1) Ativar UFW\n2) Desativar UFW\n3) Status UFW"
                read -p "Escolha: " u_opt
                if [ "$u_opt" = "1" ]; then ufw --force enable; elif [ "$u_opt" = "2" ]; then ufw --force disable; else ufw status verbose; fi
                pausa
                ;;
            5|05)
                ufw default deny incoming
                ufw default allow outgoing
                ufw allow ssh
                ufw --force enable
                echo -e "${GREEN}Regras básicas aplicadas (SSH permitido, tráfego de entrada bloqueado por padrão).${NC}"
                log_action "Aplicou regras básicas de firewall"
                pausa
                ;;
            6|06)
                ss -tuln
                pausa
                ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# 06 — Domínios / DNS
menu_dominios() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}            06 — DOMÍNIOS / DNS               ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Verificar DNS de um domínio           ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Configurar Hostname do Servidor       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Alterar Servidores DNS (Resolv.conf)  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_dom

        case $op_dom in
            1|01)
                read -p "Digite o domínio (ex: meudominio.com): " dom_check
                nslookup "$dom_check" 2>/dev/null || dig "$dom_check" 2>/dev/null || host "$dom_check" 2>/dev/null || echo -e "${RED}Ferramentas de DNS não instaladas.${NC}"
                pausa
                ;;
            2|02)
                read -p "Novo hostname: " novo_host
                hostnamectl set-hostname "$novo_host"
                echo -e "${GREEN}Hostname alterado para $novo_host${NC}"
                log_action "Alterou hostname para $novo_host"
                pausa
                ;;
            3|03)
                echo -e "1) Cloudflare + Google\n2) Apenas Google\n3) Apenas Cloudflare"
                read -p "Escolha: " dns_opt
                case $dns_opt in
                    1) printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\n" > /etc/resolv.conf ;;
                    2) printf "nameserver 8.8.8.8\nnameserver 8.8.4.4\n" > /etc/resolv.conf ;;
                    3) printf "nameserver 1.1.1.1\nnameserver 1.0.0.1\n" > /etc/resolv.conf ;;
                esac
                echo -e "${GREEN}DNS configurado com sucesso!${NC}"
                log_action "Alterou servidores DNS (opcao $dns_opt)"
                pausa
                ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# 07 — Instalar Aplicativos
menu_aplicativos() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}         07 — INSTALAR APLICATIVOS            ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Nginx        ${YELLOW}[06]${NC} Python                  ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Apache       ${YELLOW}[07]${NC} PHP                     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Docker       ${YELLOW}[08]${NC} MariaDB                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[04]${NC} Git          ${YELLOW}[09]${NC} PostgreSQL              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[05]${NC} Node.js      ${YELLOW}[10]${NC} Certbot (SSL)           ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_app

        case $op_app in
            1|01) apt-get install -y nginx; echo -e "${GREEN}Nginx instalado!${NC}"; log_action "Instalou Nginx"; pausa ;;
            2|02) apt-get install -y apache2; echo -e "${GREEN}Apache instalado!${NC}"; log_action "Instalou Apache"; pausa ;;
            3|03) curl -fsSL https://get.docker.com | bash; echo -e "${GREEN}Docker instalado!${NC}"; log_action "Instalou Docker"; pausa ;;
            4|04) apt-get install -y git; echo -e "${GREEN}Git instalado!${NC}"; log_action "Instalou Git"; pausa ;;
            5|05) curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && apt-get install -y nodejs; echo -e "${GREEN}Node.js instalado!${NC}"; log_action "Instalou Node.js"; pausa ;;
            6|06) apt-get install -y python3 python3-pip; echo -e "${GREEN}Python instalado!${NC}"; log_action "Instalou Python"; pausa ;;
            7|07) apt-get install -y php libapache2-mod-php php-mysql; echo -e "${GREEN}PHP instalado!${NC}"; log_action "Instalou PHP"; pausa ;;
            8|08) apt-get install -y mariadb-server; echo -e "${GREEN}MariaDB instalado!${NC}"; log_action "Instalou MariaDB"; pausa ;;
            9|09) apt-get install -y postgresql postgresql-contrib; echo -e "${GREEN}PostgreSQL instalado!${NC}"; log_action "Instalou PostgreSQL"; pausa ;;
            10) apt-get install -y certbot; echo -e "${GREEN}Certbot instalado!${NC}"; log_action "Instalou Certbot"; pausa ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# 08 — Docker
menu_docker() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}                  08 — DOCKER                 ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Listar containers ativos              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Listar todos os containers            ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Parar container                       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[04]${NC} Iniciar container                     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[05]${NC} Remover container                     ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[06]${NC} Ver logs de um container              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_doc

        case $op_doc in
            1|01) docker ps; pausa ;;
            2|02) docker ps -a; pausa ;;
            3|03) read -p "ID ou Nome do container: " dc_p; docker stop "$dc_p"; pausa ;;
            4|04) read -p "ID ou Nome do container: " dc_i; docker start "$dc_i"; pausa ;;
            5|05) read -p "ID ou Nome do container: " dc_r; docker rm -f "$dc_r"; pausa ;;
            6|06) read -p "ID ou Nome do container: " dc_l; docker logs "$dc_l"; pausa ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# 09 — AUTOMAÇÃO (o servidor gerencia sozinho)
auto_watchdog_on() {
    mkdir -p "$VPS_DIR"
    cat > "$VPS_DIR/watchdog.sh" <<'EOF'
#!/bin/bash
# Watchdog VPS MANAGER PRO - reinicia servicos caidos
for svc in ssh xray nginx apache2 cron; do
    if systemctl list-unit-files "$svc.service" &>/dev/null && systemctl is-enabled --quiet "$svc" 2>/dev/null; then
        systemctl is-active --quiet "$svc" || {
            systemctl restart "$svc"
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] WATCHDOG: $svc estava parado e foi reiniciado" >> /var/log/vps_manager.log
        }
    fi
done
EOF
    chmod +x "$VPS_DIR/watchdog.sh"
    (crontab -l 2>/dev/null | grep -v "vpsmanager/watchdog.sh"; echo "*/2 * * * * $VPS_DIR/watchdog.sh # VPSMANAGER") | crontab -
    systemctl restart cron 2>/dev/null
    echo -e "${GREEN}✔ Watchdog ATIVADO! Verifica SSH/Xray/Nginx/Apache/Cron a cada 2 minutos.${NC}"
    log_action "Ativou watchdog de servicos"
}
auto_watchdog_off() {
    (crontab -l 2>/dev/null | grep -v "vpsmanager/watchdog.sh") | crontab -
    echo -e "${YELLOW}Watchdog DESATIVADO.${NC}"
    log_action "Desativou watchdog de servicos"
}
auto_expclean_on() {
    mkdir -p "$VPS_DIR"
    cat > "$VPS_DIR/expclean.sh" <<'EOF'
#!/bin/bash
# Remove usuarios SSH com validade (chage) vencida
while IFS= read -r user; do
    exp=$(chage -l "$user" 2>/dev/null | awk -F: '/Account expires/{sub(/^ */,"",$2); print $2}')
    [[ -z "$exp" || "$exp" == never* ]] && continue
    exp_sec=$(date +%s --date="$exp" 2>/dev/null) || continue
    if [[ $(date +%s) -gt $exp_sec ]]; then
        pkill -u "$user" 2>/dev/null
        userdel -r "$user" 2>/dev/null
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] EXPIRADOS: usuario $user removido (venceu em $exp)" >> /var/log/vps_manager.log
    fi
done < <(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd)
EOF
    chmod +x "$VPS_DIR/expclean.sh"
    (crontab -l 2>/dev/null | grep -v "vpsmanager/expclean.sh"; echo "0 */6 * * * $VPS_DIR/expclean.sh # VPSMANAGER") | crontab -
    systemctl restart cron 2>/dev/null
    echo -e "${GREEN}✔ Remoção automática de expirados ATIVADA! (verifica a cada 6 horas)${NC}"
    log_action "Ativou remocao automatica de expirados"
}
auto_expclean_off() {
    (crontab -l 2>/dev/null | grep -v "vpsmanager/expclean.sh") | crontab -
    echo -e "${YELLOW}Remoção automática de expirados DESATIVADA.${NC}"
    log_action "Desativou remocao automatica de expirados"
}
auto_backup_on() {
    mkdir -p "$VPS_DIR" /root/backups
    cat > "$VPS_DIR/autobackup.sh" <<'EOF'
#!/bin/bash
# Backup automatico diario (mantem os ultimos 7)
B=/root/backups/auto_backup_$(date +%Y%m%d_%H%M%S).tar.gz
tar -czf "$B" /etc /home 2>/dev/null
echo "[$(date '+%Y-%m-%d %H:%M:%S')] BACKUP AUTOMATICO criado: $B" >> /var/log/vps_manager.log
ls -1t /root/backups/auto_backup_*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm -f
EOF
    chmod +x "$VPS_DIR/autobackup.sh"
    (crontab -l 2>/dev/null | grep -v "vpsmanager/autobackup.sh"; echo "0 4 * * * $VPS_DIR/autobackup.sh # VPSMANAGER") | crontab -
    systemctl restart cron 2>/dev/null
    echo -e "${GREEN}✔ Backup automático ATIVADO! Diário às 04:00 (mantém os últimos 7).${NC}"
    log_action "Ativou backup automatico diario"
}
auto_backup_off() {
    (crontab -l 2>/dev/null | grep -v "vpsmanager/autobackup.sh") | crontab -
    echo -e "${YELLOW}Backup automático DESATIVADO.${NC}"
    log_action "Desativou backup automatico diario"
}
menu_automacao() {
    while true; do
        clear
        local wd ex bk
        crontab -l 2>/dev/null | grep -q "vpsmanager/watchdog.sh" && wd="${GREEN}◉${NC}" || wd="${RED}○${NC}"
        crontab -l 2>/dev/null | grep -q "vpsmanager/expclean.sh" && ex="${GREEN}◉${NC}" || ex="${RED}○${NC}"
        crontab -l 2>/dev/null | grep -q "vpsmanager/autobackup.sh" && bk="${GREEN}◉${NC}" || bk="${RED}○${NC}"
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}        09 — AUTOMAÇÃO DO SERVIDOR            ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Watchdog de serviços $wd              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}      (reinicia SSH/Xray/Nginx se caírem)   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Remover usuários expirados $ex        ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}      (executa a cada 6 horas)              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Backup automático diário $bk          ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}      (04:00, mantém últimos 7)             ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[04]${NC} Ver tarefas automáticas (crontab)    ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_auto

        case $op_auto in
            1|01)
                if crontab -l 2>/dev/null | grep -q "vpsmanager/watchdog.sh"; then auto_watchdog_off; else auto_watchdog_on; fi
                pausa
                ;;
            2|02)
                if crontab -l 2>/dev/null | grep -q "vpsmanager/expclean.sh"; then auto_expclean_off; else auto_expclean_on; fi
                pausa
                ;;
            3|03)
                if crontab -l 2>/dev/null | grep -q "vpsmanager/autobackup.sh"; then auto_backup_off; else auto_backup_on; fi
                pausa
                ;;
            4|04)
                echo -e "\n${BLUE}=== Tarefas agendadas (crontab) ===${NC}"
                crontab -l 2>/dev/null || echo "Crontab vazio."
                pausa
                ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# 10 — Rede / IP / Portas
menu_rede() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}             10 — REDE / IP / PORTAS          ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Ver IP Público                        ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Ver Interfaces de Rede                ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Testar velocidade (Speedtest)         ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[04]${NC} Analisar tráfego de rede              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_rede

        case $op_rede in
            1|01)
                curl -s4 ifconfig.me || curl -s4 ipv4.icanhazip.com
                echo ""
                pausa
                ;;
            2|02)
                ip a
                pausa
                ;;
            3|03)
                if ! command -v speedtest &> /dev/null; then
                    curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash
                    apt-get install -y speedtest
                fi
                speedtest
                pausa
                ;;
            4|04)
                if ! command -v iftop &> /dev/null; then apt-get install -y iftop; fi
                iftop
                pausa
                ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# 11 — Backup / Restore
menu_backup() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}             11 — BACKUP / RESTORE            ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Criar backup geral (/etc e home)      ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Listar backups salvos                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Restaurar um backup                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_bkp

        case $op_bkp in
            1|01)
                mkdir -p /root/backups
                b_name="/root/backups/backup_vps_$(date +%Y%m%d_%H%M%S).tar.gz"
                tar -czf "$b_name" /etc /root /home 2>/dev/null
                echo -e "${GREEN}Backup criado com sucesso em: $b_name${NC}"
                log_action "Criou backup manual: $b_name"
                pausa
                ;;
            2|02)
                ls -lh /root/backups/ 2>/dev/null || echo "Nenhum backup encontrado."
                pausa
                ;;
            3|03)
                echo -e "\n${BLUE}=== Restaurar Backup ===${NC}"
                ls -1 /root/backups/*.tar.gz 2>/dev/null | cat -n
                read -p "Número do backup a restaurar: " b_num
                b_file=$(ls -1 /root/backups/*.tar.gz 2>/dev/null | sed -n "${b_num}p")
                if [[ -n "$b_file" && -f "$b_file" ]]; then
                    read -p "Confirma a restauração em / ? (s/n): " b_conf
                    if [[ "$b_conf" =~ ^[sS]$ ]]; then
                        tar -xzf "$b_file" -C /
                        echo -e "${GREEN}Backup restaurado!${NC}"
                        log_action "Restaurou backup: $b_file"
                    fi
                else
                    echo -e "${RED}Backup inválido!${NC}"
                fi
                pausa
                ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# 12 — Atualizar Sistema
menu_atualizar() {
    clear
    echo -e "${BLUE}=== Atualizando Sistema ===${NC}"
    apt-get update -y && apt-get upgrade -y && apt-get dist-upgrade -y && apt-get autoremove -y
    echo -e "${GREEN}Sistema atualizado com sucesso!${NC}"
    log_action "Atualizou o sistema operacional"
    pausa
}

# 13 — Ferramentas do Linux
menu_ferramentas() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}           13 — FERRAMENTAS DO LINUX          ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Limpar cache de memória RAM           ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Verificar espaço em arquivos temporários${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Alterar fuso horário (Timezone)       ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[04]${NC} Limpar logs antigos                   ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_fer

        case $op_fer in
            1|01)
                sync && echo 3 > /proc/sys/vm/drop_caches
                echo -e "${GREEN}Cache de RAM limpo!${NC}"
                log_action "Limpou cache de RAM"
                pausa
                ;;
            2|02)
                df -h /tmp
                echo ""
                du -sh /tmp/* 2>/dev/null | sort -rh | head -10
                pausa
                ;;
            3|03)
                dpkg-reconfigure tzdata
                log_action "Alterou timezone"
                pausa
                ;;
            4|04)
                journalctl --vacuum-time=7d > /dev/null 2>&1
                find /var/log -name "*.gz" -mtime +7 -delete 2>/dev/null
                find /var/log -name "*.1" -mtime +7 -delete 2>/dev/null
                echo -e "${GREEN}Logs com mais de 7 dias removidos!${NC}"
                log_action "Limpou logs antigos"
                pausa
                ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# 14 — Logs do Servidor
menu_logs() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}             14 — LOGS DO SERVIDOR            ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Logs de autenticação SSH (/var/log/auth.log)${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Logs do Sistema (Syslog)              ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} Logs do Gerenciador VPS               ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_log

        case $op_log in
            1|01) tail -n 50 /var/log/auth.log 2>/dev/null || journalctl -u ssh -n 50 --no-pager; pausa ;;
            2|02) tail -n 50 /var/log/syslog 2>/dev/null || journalctl -n 50 --no-pager; pausa ;;
            3|03) tail -n 50 "$LOG_FILE" 2>/dev/null || echo "Sem registros."; pausa ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# 15 — Configurações / Instalação do Comando
menu_config() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}              15 — CONFIGURAÇÕES              ${CYAN}║${NC}"
        echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} Instalar atalho global (comando 'vps') ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} Atualizar este script                 ${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${RED}[00]${NC} Voltar ao menu principal              ${CYAN}║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
        echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
        read op_cfg

        case $op_cfg in
            1|01)
                if [ -f "$0" ] && [[ "$0" != /dev/fd/* && "$0" != /proc/self/fd/* ]]; then
                    cp "$0" /usr/local/bin/vps
                elif [ -f /usr/local/bin/vps ]; then
                    echo -e "${YELLOW}Atalho já existe, mantendo versão atual.${NC}"
                else
                    curl -sL "$SCRIPT_URL" -o /usr/local/bin/vps
                fi
                chmod +x /usr/local/bin/vps
                echo -e "${GREEN}Comando 'vps' instalado com sucesso! Agora basta digitar 'vps' em qualquer lugar.${NC}"
                log_action "Instalou atalho global 'vps'"
                pausa
                ;;
            2|02)
                echo -e "${YELLOW}Baixando versão mais recente do repositório...${NC}"
                curl -sL "$SCRIPT_URL" -o /tmp/vpsmanager_new.sh
                if grep -q "VPS MANAGER PRO" /tmp/vpsmanager_new.sh 2>/dev/null; then
                    chmod +x /tmp/vpsmanager_new.sh
                    if [ -f /usr/local/bin/vps ]; then
                        cp /tmp/vpsmanager_new.sh /usr/local/bin/vps
                    fi
                    if [ -f "$0" ] && [[ "$0" != /dev/fd/* && "$0" != /proc/self/fd/* ]]; then
                        cp /tmp/vpsmanager_new.sh "$0"
                    fi
                    echo -e "${GREEN}Script atualizado! Reinicie o painel para aplicar.${NC}"
                    log_action "Atualizou o script VPS Manager Pro"
                else
                    echo -e "${RED}Falha ao baixar atualização (verifique a branch/ref).${NC}"
                fi
                rm -f /tmp/vpsmanager_new.sh
                pausa
                ;;
            0|00) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 1 ;;
        esac
    done
}

# ==============================================================================
# INICIALIZAÇÃO DO AMBIENTE AUTOMAÇÃO
# ==============================================================================
mkdir -p "$VPS_DIR" /root/backups 2>/dev/null

# ==============================================================================
# MENU PRINCIPAL (SEM MONITORAMENTO)
# ==============================================================================
while true; do
    clear

    echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${GREEN}               VPS MANAGER PRO                ${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}            Gerenciador de Servidor           ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}                                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[01]${NC} 👤 GERENCIAR USUÁRIOS SSH            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[02]${NC} 🔐 SENHAS / ACESSOS                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[03]${NC} 🌐 XRAY / V2RAY                      ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[04]${NC} 🚀 SERVIÇOS DO SERVIDOR              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[05]${NC} 🔥 FIREWALL / PORTAS                 ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[06]${NC} 🌍 DOMÍNIOS / DNS                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[07]${NC} 📦 INSTALAR APLICATIVOS              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[08]${NC} 🐳 DOCKER                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[09]${NC} 🤖 AUTOMAÇÃO DO SERVIDOR             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[10]${NC} 🌐 REDE / IP / PORTAS                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[11]${NC} 💾 BACKUP / RESTORE                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[12]${NC} 🔄 ATUALIZAR SISTEMA               ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[13]${NC} 🛠️  FERRAMENTAS DO LINUX             ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[14]${NC} 📜 LOGS DO SERVIDOR                  ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${YELLOW}[15]${NC} 🔧 CONFIGURAÇÕES                   ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${RED}[00]${NC} ❌ SAIR                              ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                              ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
    echo -n -e "${GREEN}Digite a opção desejada: ${NC}"
    read opcao_principal

    case $opcao_principal in
        1|01) menu_ssh ;;
        2|02) menu_senhas ;;
        3|03) menu_xray ;;
        4|04) menu_servicos ;;
        5|05) menu_firewall ;;
        6|06) menu_dominios ;;
        7|07) menu_aplicativos ;;
        8|08) menu_docker ;;
        9|09) menu_automacao ;;
        10) menu_rede ;;
        11) menu_backup ;;
        12) menu_atualizar ;;
        13) menu_ferramentas ;;
        14) menu_logs ;;
        15) menu_config ;;
        0|00)
            echo -e "\n${GREEN}Saindo do painel VPS Manager Pro. Até logo!${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}Opção inválida!${NC}"
            sleep 1
            ;;
    esac
done
