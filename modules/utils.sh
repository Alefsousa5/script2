# ============================================================================
# MÓDULO DE FERRAMENTAS ÚTEIS
# ============================================================================

menu_utils() {
    while true; do
        banner_init
        echo -e "${BG_RED}${BOLD}${WHITE}        🛠️ FERRAMENTAS ÚTEIS                           ${RESET}"
        echo ""
        echo -e "${BOLD}${WHITE}  [ 1 ]${RESET} Speedtest (teste de velocidade)"
        echo -e "${BOLD}${WHITE}  [ 2 ]${RESET} Ping para vários destinos"
        echo -e "${BOLD}${WHITE}  [ 3 ]${RESET} Verificar portas abertas (UFW/iptables)"
        echo -e "${BOLD}${WHITE}  [ 4 ]${RESET} Liberar porta no firewall"
        echo -e "${BOLD}${WHITE}  [ 5 ]${RESET} Backup de configs (SSH + Xray)"
        echo -e "${BOLD}${WHITE}  [ 6 ]${RESET} Limpar logs"
        echo -e "${BOLD}${WHITE}  [ 7 ]${RESET} Atualizar sistema (apt update/upgrade)"
        echo -e "${BOLD}${WHITE}  [ 8 ]${RESET} Desligar/Reiniciar VPS"
        echo -e "${BOLD}${WHITE}  [ 9 ]${RESET} Trocar senha do root"
        echo -e "${BOLD}${WHITE}  [10 ]${RESET} Verificar IP público/local"
        echo -e "${BOLD}${WHITE}  [11 ]${RESET} Limpeza de contas expiradas (Xray e SSH)"
        echo -e "${BOLD}${WHITE}  [12 ]${RESET} Sobre o painel"
        echo ""
        echo -e "${BOLD}${WHITE}  [ 0 ]${RESET} Voltar"
        echo ""
        linha_dupla

        ler_input "  Escolha" "" op
        case "$op" in
            1) util_speedtest ;;
            2) util_ping ;;
            3) util_firewall_status ;;
            4) util_liberar_porta ;;
            5) util_backup ;;
            6) util_limpar_logs ;;
            7) util_atualizar ;;
            8) util_reboot_shutdown ;;
            9) util_senha_root ;;
            10) util_ips ;;
            11) util_limpar_expiradas ;;
            12) util_sobre ;;
            0) return ;;
            *) echo -e "${RED}Inválido!${RESET}"; sleep 1 ;;
        esac
    done
}

util_speedtest() {
    clear
    linha
    echo -e "${BOLD}TESTE DE VELOCIDADE${RESET}"
    linha
    if ! command -v speedtest-cli &>/dev/null && ! command -v speedtest &>/dev/null; then
        info "Instalando speedtest-cli..."
        if command -v apt &>/dev/null; then
            apt install -y -qq speedtest-cli >/dev/null 2>&1 || \
                pip install speedtest-cli >/dev/null 2>&1 || {
                warn "Tentando pelo script oficial Ookla..."
                curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | bash >/dev/null 2>&1
                apt install -y speedtest >/dev/null 2>&1
            }
        fi
    fi
    if command -v speedtest &>/dev/null; then
        speedtest --accept-license --accept-gdpr 2>&1 | head -30
    elif command -v speedtest-cli &>/dev/null; then
        speedtest-cli --simple 2>&1
    else
        error "Não foi possível instalar o speedtest."
        info "Teste manual: faça download de um arquivo grande para verificar."
    fi
    pause
}

util_ping() {
    clear
    linha
    echo -e "${BOLD}PING PARA DESTINOS COMUNS${RESET}"
    linha
    for dest in google.com 8.8.8.8 1.1.1.1 cloudflare.com; do
        echo -e "${CYAN}Ping para $dest:${RESET}"
        ping -c 3 -W 2 "$dest" 2>&1 | tail -3
        echo ""
    done
    pause
}

util_firewall_status() {
    clear
    linha
    echo -e "${BOLD}STATUS DO FIREWALL${RESET}"
    linha
    if command -v ufw &>/dev/null; then
        echo -e "${BOLD}UFW:${RESET}"
        ufw status verbose 2>/dev/null | head -40
    fi
    echo ""
    echo -e "${BOLD}IPTABLES (regras NAT/FILTER):${RESET}"
    iptables -L -n 2>/dev/null | head -40
    echo ""
    echo -e "${BOLD}Portas em modo LISTEN:${RESET}"
    ss -tulnp 2>/dev/null | awk 'NR==1 {print}; NR>1 && $1 ~ /LISTEN/ {print}'
    pause
}

util_liberar_porta() {
    clear
    linha
    echo -e "${BOLD}LIBERAR PORTA NO FIREWALL${RESET}"
    linha
    ler_input "Porta a liberar" "" porta
    [ -z "$porta" ] && return
    ler_input "Protocolo (tcp/udp/both)" "tcp" proto
    if command -v ufw &>/dev/null; then
        if [ "$proto" = "both" ]; then
            ufw allow "$porta"
        else
            ufw allow "$porta/$proto"
        fi
        ufw status | grep "$porta"
        sucesso "Porta $porta liberada no UFW."
    else
        warn "UFW não está instalado. Usando iptables."
        if [ "$proto" = "tcp" ] || [ "$proto" = "both" ]; then
            iptables -I INPUT -p tcp --dport "$porta" -j ACCEPT
        fi
        if [ "$proto" = "udp" ] || [ "$proto" = "both" ]; then
            iptables -I INPUT -p udp --dport "$porta" -j ACCEPT
        fi
        iptables-save > /etc/iptables.rules 2>/dev/null
        sucesso "Regra iptables adicionada (não persistente por padrão)."
    fi
    pause
}

util_backup() {
    clear
    linha
    echo -e "${BOLD}BACKUP DE CONFIGS${RESET}"
    linha
    BKP_DIR="$SCRIPT_DIR/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BKP_DIR"
    if [ -f "$SSH_CONFIG" ]; then
        cp "$SSH_CONFIG" "$BKP_DIR/sshd_config"
        sucesso "Backup sshd_config"
    fi
    if [ -f "$XRAY_CONFIG" ]; then
        cp -r "$XRAY_DIR" "$BKP_DIR/xray"
        sucesso "Backup config Xray"
    fi
    # Lista de usuários
    awk -F: '$3>=1000 && $3<65534 {print $1}' /etc/passwd > "$BKP_DIR/usuarios.txt"
    sucesso "Lista de usuários salva"
    echo ""
    info "Backup salvo em: $BKP_DIR"
    echo ""
    ls -lh "$BKP_DIR"
    pause
}

util_limpar_logs() {
    clear
    linha
    echo -e "${BOLD}LIMPEZA DE LOGS${RESET}"
    linha
    echo "Logs atuais:"
    du -sh /var/log/* 2>/dev/null | sort -h | tail -15
    echo ""
    ler_input "Confirmar limpeza? (s/n)" "n" conf
    if [ "$conf" = "s" ]; then
        find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null
        find /var/log -type f -name "*.gz" -delete 2>/dev/null
        journalctl --vacuum-time=1d >/dev/null 2>&1
        sucesso "Logs limpos."
    else
        warn "Cancelado."
    fi
    pause
}

util_atualizar() {
    clear
    linha
    echo -e "${BOLD}ATUALIZAÇÃO DO SISTEMA${RESET}"
    linha
    if command -v apt &>/dev/null; then
        apt update && apt list --upgradable 2>/dev/null | head -30
        echo ""
        ler_input "Deseja executar apt upgrade? (s/n)" "n" conf
        if [ "$conf" = "s" ]; then
            apt upgrade -y
        fi
    elif command -v yum &>/dev/null; then
        yum check-update
        ler_input "Executar yum update? (s/n)" "n" conf
        [ "$conf" = "s" ] && yum update -y
    fi
    pause
}

util_reboot_shutdown() {
    clear
    linha
    echo -e "${RED}${BOLD}DESLIGAR/REINICIAR VPS${RESET}"
    linha
    echo "1 - Reiniciar VPS agora"
    echo "2 - Desligar VPS agora"
    echo "0 - Cancelar"
    ler_input "Opção" "" op
    case "$op" in
        1) warn "Reiniciando em 5 segundos..."; sleep 5; reboot ;;
        2) warn "Desligando em 5 segundos..."; sleep 5; poweroff ;;
    esac
}

util_senha_root() {
    clear
    linha
    echo -e "${BOLD}ALTERAR SENHA DO ROOT${RESET}"
    linha
    passwd root
    echo "[$(date)] Senha do root alterada" >> "$PAINEL_LOG"
    pause
}

util_ips() {
    clear
    linha
    echo -e "${BOLD}IPS DO SERVIDOR${RESET}"
    linha
    echo -e "  IP Público IPv4: ${GREEN}$(get_ip_publico)${RESET}"
    local ip6
    ip6=$(get_ip6_publico)
    [ -n "$ip6" ] && echo -e "  IP Público IPv6: ${GREEN}$ip6${RESET}"
    echo ""
    echo -e "${BOLD}IPs privados:${RESET}"
    ip -br addr 2>/dev/null
    pause
}

util_limpar_expiradas() {
    clear
    linha
    echo -e "${BOLD}LIMPEZA DE CONTAS EXPIRADAS${RESET}"
    linha
    local hoje
    hoje=$(date +%Y-%m-%d)
    local hoje_ts
    hoje_ts=$(date +%s)
    local removidas=0

    if [ -f "$XRAY_CONFIG" ]; then
        info "Verificando contas Xray expiradas..."
        cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
        tmp=$(mktemp)
        jq --arg hoje "$hoje" --argjson hts "$hoje_ts" '
            .inbounds |= map(
                .settings.clients = ((.settings.clients // []) | map(
                    if (.expira // "") == "" then .
                    else
                        (.expira | strptime("%Y-%m-%d") | mktime) as $ets |
                        if $ets < $hts then empty else . end
                    end
                ))
            )
        ' "$XRAY_CONFIG" > "$tmp"
        local contas_antes contas_depois
        contas_antes=$(jq '[.inbounds[].settings.clients[]] | length' "$XRAY_CONFIG")
        mv "$tmp" "$XRAY_CONFIG"
        contas_depois=$(jq '[.inbounds[].settings.clients[]] | length' "$XRAY_CONFIG")
        removidas=$((contas_antes - contas_depois))
        if [ "$removidas" -gt 0 ]; then
            xray run -test -config "$XRAY_CONFIG" >/dev/null 2>&1 && systemctl restart xray
            sucesso "Removidas $removidas conta(s) Xray expiradas."
        else
            info "Nenhuma conta Xray expirada."
        fi
    fi

    # Usuários SSH expirados (aviso apenas)
    echo ""
    info "Usuários SSH com data de expiração já passada:"
    while IFS=: read -r usuario _ uid _ _ _ _; do
        if [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ]; then
            expira=$(chage -l "$usuario" 2>/dev/null | grep "Account expires" | cut -d: -f2 | sed 's/^ *//')
            if [ -n "$expira" ] && [[ "$expira" != *"never"* ]] && [[ "$expira" != *"nunca"* ]]; then
                exp_ts=$(date -d "$expira" +%s 2>/dev/null)
                if [ -n "$exp_ts" ] && [ "$exp_ts" -lt "$hoje_ts" ]; then
                    echo -e "  ${RED}$usuario${RESET} - expirou em $expira"
                fi
            fi
        fi
    done < /etc/passwd
    echo "[$(date)] Limpeza de contas expiradas: $removidas Xray" >> "$PAINEL_LOG"
    pause
}

util_sobre() {
    clear
    linha_dupla
    echo -e "${BOLD}  🚀 PAINEL SSH + XRAY v1.0${RESET}"
    linha_dupla
    echo ""
    echo "  Desenvolvido para facilitar o gerenciamento de VPS"
    echo "  voltada para SSH e Xray (VLESS/VMess/Trojan)."
    echo ""
    echo "  Recursos:"
    echo "    • Criação/remoção/listagem de usuários SSH"
    echo "    • Alteração de porta SSH e segurança"
    echo "    • Criação de contas VLESS, VMess e Trojan"
    echo "    • Links e QR Codes prontos para importar no app"
    echo "    • Validade de contas e limpeza de expiradas"
    echo "    • Monitor de conexões em tempo real"
    echo "    • Informações completas do sistema"
    echo "    • Ferramentas: speedtest, ping, backup, firewall"
    echo ""
    echo "  Compatível com Debian/Ubuntu e derivados."
    echo "  Requer: root, systemd, bash 4+, jq"
    echo ""
    echo -e "  Diretório do painel: ${CYAN}$SCRIPT_DIR${RESET}"
    echo -e "  Log do painel: ${CYAN}$PAINEL_LOG${RESET}"
    echo ""
    linha_dupla
    pause
}

# ============================================================================
# MENU DE LOGS
# ============================================================================

menu_logs() {
    while true; do
        banner_init
        echo -e "${BG_CYAN}${BOLD}${WHITE}        📋 LOGS DO SISTEMA                              ${RESET}"
        echo ""
        echo -e "${BOLD}${WHITE}  [ 1 ]${RESET} Logs do Xray (access.log)"
        echo -e "${BOLD}${WHITE}  [ 2 ]${RESET} Logs de erro do Xray (error.log)"
        echo -e "${BOLD}${WHITE}  [ 3 ]${RESET} Logs de autenticação SSH (auth.log)"
        echo -e "${BOLD}${WHITE}  [ 4 ]${RESET} Log do systemd (journalctl) - Xray"
        echo -e "${BOLD}${WHITE}  [ 5 ]${RESET} Log do painel"
        echo -e "${BOLD}${WHITE}  [ 6 ]${RESET} Acompanhar logs em tempo real (tail -f)"
        echo ""
        echo -e "${BOLD}${WHITE}  [ 0 ]${RESET} Voltar"
        echo ""
        linha_dupla
        ler_input "  Escolha" "" op
        case "$op" in
            1)
                clear
                if [ -f /var/log/xray/access.log ]; then
                    tail -n 100 /var/log/xray/access.log
                else
                    error "access.log não encontrado."
                fi
                pause ;;
            2)
                clear
                if [ -f /var/log/xray/error.log ]; then
                    tail -n 100 /var/log/xray/error.log
                else
                    error "error.log não encontrado."
                fi
                pause ;;
            3)
                clear
                if [ -f /var/log/auth.log ]; then
                    tail -n 100 /var/log/auth.log
                elif [ -f /var/log/secure ]; then
                    tail -n 100 /var/log/secure
                else
                    error "Log de auth não encontrado."
                fi
                pause ;;
            4)
                clear
                journalctl -u xray --no-pager -n 100
                pause ;;
            5)
                clear
                if [ -f "$PAINEL_LOG" ]; then
                    cat "$PAINEL_LOG"
                else
                    info "Log do painel ainda não existe."
                fi
                pause ;;
            6)
                echo -e "${YELLOW}Escolha: 1-Xray access, 2-Xray error, 3-SSH auth${RESET}"
                ler_input "Arquivo" "1" arq
                case "$arq" in
                    1) f=/var/log/xray/access.log ;;
                    2) f=/var/log/xray/error.log ;;
                    3) f=/var/log/auth.log; [ ! -f "$f" ] && f=/var/log/secure ;;
                    *) f="" ;;
                esac
                if [ -n "$f" ] && [ -f "$f" ]; then
                    echo -e "${YELLOW}Acompanhando $f - pressione Ctrl+C para sair${RESET}"
                    sleep 2
                    tail -f "$f"
                else
                    error "Arquivo não encontrado: $f"
                    sleep 2
                fi
                ;;
            0) return ;;
            *) echo -e "${RED}Inválido!${RESET}"; sleep 1 ;;
        esac
    done
}
