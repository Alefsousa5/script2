# ============================================================================
# MÓDULO DE MONITORAMENTO DE CONEXÕES
# ============================================================================

menu_monitor() {
    while true; do
        banner_init
        echo -e "${BG_BLUE}${BOLD}${WHITE}        👁️ MONITOR DE CONEXÕES                         ${RESET}"
        echo ""
        echo -e "${BOLD}${WHITE}  [ 1 ]${RESET} Conexões SSH ativas"
        echo -e "${BOLD}${WHITE}  [ 2 ]${RESET} Conexões Xray ativas"
        echo -e "${BOLD}${WHITE}  [ 3 ]${RESET} Todos os sockets abertos"
        echo -e "${BOLD}${WHITE}  [ 4 ]${RESET} Últimos logins SSH"
        echo -e "${BOLD}${WHITE}  [ 5 ]${RESET} Tentativas de acesso (fail2ban/auth.log)"
        echo -e "${BOLD}${WHITE}  [ 6 ]${RESET} Tráfego em tempo real (iftop/ss)"
        echo -e "${BOLD}${WHITE}  [ 7 ]${RESET} Uso de banda por processo"
        echo -e "${BOLD}${WHITE}  [ 8 ]${RESET} Quem está conectado agora"
        echo ""
        echo -e "${BOLD}${WHITE}  [ 0 ]${RESET} Voltar"
        echo ""
        linha_dupla

        ler_input "  Escolha" "" op
        case "$op" in
            1) monitor_ssh ;;
            2) monitor_xray ;;
            3) monitor_sockets ;;
            4) monitor_logins ;;
            5) monitor_tentativas ;;
            6) monitor_trafego ;;
            7) monitor_banda_proc ;;
            8) monitor_who ;;
            0) return ;;
            *) echo -e "${RED}Inválido!${RESET}"; sleep 1 ;;
        esac
    done
}

monitor_ssh() {
    clear
    linha
    echo -e "${BOLD}CONEXÕES SSH ATIVAS (porta 22 ou porta configurada)${RESET}"
    linha
    local port
    port=$(grep -E "^Port\s+" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}')
    port="${port:-22}"
    echo -e "${BOLD}Porta: $port${RESET}"
    echo ""
    ss -tnp 2>/dev/null | grep -E "(:$port\s|sshd)" | head -50
    echo ""
    echo -e "${BOLD}Processos SSHD:${RESET}"
    ps -eo pid,user,cmd | grep -E '[s]shd:' | head -30
    pause
}

monitor_xray() {
    clear
    linha
    echo -e "${BOLD}CONEXÕES XRAY ATIVAS${RESET}"
    linha
    ss -tnp 2>/dev/null | grep -i xray | head -100
    echo ""
    linha
    echo -e "${BOLD}PROCESSO XRAY:${RESET}"
    ps -eo pid,%cpu,%mem,cmd | grep -i '[x]ray' | head -10
    if [ -f /var/log/xray/access.log ]; then
        echo ""
        linha
        echo -e "${BOLD}ÚLTIMAS 30 LINHAS DO ACCESS LOG:${RESET}"
        tail -30 /var/log/xray/access.log
    fi
    pause
}

monitor_sockets() {
    clear
    linha
    echo -e "${BOLD}SOCKETS ABERTOS (listen)${RESET}"
    linha
    ss -tulnp 2>/dev/null | head -50
    echo ""
    echo -e "${GRAY}(Para ver tudo: ss -tulnp | less)${RESET}"
    pause
}

monitor_logins() {
    clear
    linha
    echo -e "${BOLD}ÚLTIMOS LOGINS SSH (last)${RESET}"
    linha
    last -a 2>/dev/null | head -30
    echo ""
    linha
    echo -e "${BOLD}LOGINS ATUAIS (who/w):${RESET}"
    w 2>/dev/null
    pause
}

monitor_tentativas() {
    clear
    linha
    echo -e "${BOLD}TENTATIVAS DE ACESSO (autenticação falha)${RESET}"
    linha
    if [ -f /var/log/auth.log ]; then
        echo -e "${YELLOW}Últimas 30 falhas:${RESET}"
        grep -i "failed\|failure\|invalid" /var/log/auth.log 2>/dev/null | tail -30
    elif [ -f /var/log/secure ]; then
        grep -i "failed\|failure\|invalid" /var/log/secure 2>/dev/null | tail -30
    else
        echo "Arquivo de log de autenticação não encontrado."
    fi
    if command -v fail2ban-client &>/dev/null; then
        echo ""
        linha
        echo -e "${BOLD}STATUS FAIL2BAN:${RESET}"
        fail2ban-client status 2>/dev/null | head -20
    fi
    pause
}

monitor_trafego() {
    clear
    linha
    echo -e "${BOLD}TRÁFEGO EM TEMPO REAL${RESET}"
    linha
    echo -e "${YELLOW}Atualizando a cada 2 segundos por 10 ciclos (Ctrl+C para parar)...${RESET}"
    echo ""
    for i in $(seq 1 10); do
        clear
        echo -e "${BOLD}Ciclo $i/10 - ${CYAN}$(date +%H:%M:%S)${RESET}"
        ss -tnp 2>/dev/null | awk 'NR==1 || /ESTAB/ {print}' | head -20
        echo ""
        echo -e "${BOLD}Resumo de conexões por estado:${RESET}"
        ss -tan 2>/dev/null | awk 'NR>1 {print $1}' | sort | uniq -c
        sleep 2
    done
    pause
}

monitor_banda_proc() {
    clear
    linha
    echo -e "${BOLD}USO DE CPU/RAM DOS PRINCIPAIS PROCESSOS${RESET}"
    linha
    ps -eo pid,%cpu,%mem,rss,comm --sort=-%cpu | head -20 | \
        awk 'BEGIN{printf "%-8s %-6s %-6s %-10s %s\n","PID","%CPU","%MEM","RSS","COMANDO"}
             NR==1{print;next} {printf "%-8s %-6s %-6s %-10s %s\n",$1,$2,$3,$4/1024"M",$5}'
    pause
}

monitor_who() {
    clear
    linha
    echo -e "${BOLD}USUÁRIOS CONECTADOS AGORA${RESET}"
    linha
    w 2>/dev/null
    echo ""
    echo -e "${BOLD}who:${RESET}"
    who 2>/dev/null
    pause
}
