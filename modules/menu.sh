# ============================================================================
# MENU PRINCIPAL
# ============================================================================

menu_principal() {
    while true; do
        banner_init
        local hostname_sis
        hostname_sis=$(hostname 2>/dev/null || echo "VPS")
        local ip_pub
        ip_pub=$(get_ip_publico)
        local uptime_sis
        uptime_sis=$(uptime -p 2>/dev/null | sed 's/up //')
        local data_hora
        data_hora=$(date "+%d/%m/%Y %H:%M:%S")

        echo -e "${BOLD}  VPS:${RESET} ${GREEN}$hostname_sis${RESET}  |  ${BOLD}IP:${RESET} ${CYAN}$ip_pub${RESET}"
        echo -e "${BOLD}  Uptime:${RESET} $uptime_sis  |  ${BOLD}Data:${RESET} $data_hora"
        echo ""
        linha_dupla

        # Status dos serviços
        echo -e "${BOLD}  STATUS DOS SERVIÇOS:${RESET}"
        if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
            echo -e "    ${GREEN}● SSH${RESET} ativo"
        else
            echo -e "    ${RED}● SSH${RESET} parado"
        fi

        if [ "$XRAY_INSTALADO" -eq 1 ] && systemctl is-active --quiet xray 2>/dev/null; then
            echo -e "    ${GREEN}● Xray${RESET} ativo"
        elif [ "$XRAY_INSTALADO" -eq 1 ]; then
            echo -e "    ${RED}● Xray${RESET} parado"
        else
            echo -e "    ${GRAY}● Xray${RESET} não instalado"
        fi
        echo ""
        linha_dupla

        echo -e "${BOLD}${WHITE}  [ 1 ]${RESET} ${CYAN}Gerenciar SSH${RESET}        - Usuários, portas, chaves"
        echo -e "${BOLD}${WHITE}  [ 2 ]${RESET} ${CYAN}Gerenciar Xray${RESET}       - Contas VLESS/VMess/Trojan"
        echo -e "${BOLD}${WHITE}  [ 3 ]${RESET} ${CYAN}Informações do Sistema${RESET} - CPU, RAM, disco, rede"
        echo -e "${BOLD}${WHITE}  [ 4 ]${RESET} ${CYAN}Monitor de Conexões${RESET}   - Conexões ativas SSH/Xray"
        echo -e "${BOLD}${WHITE}  [ 5 ]${RESET} ${CYAN}Ferramentas Úteis${RESET}     - Speedtest, ping, backup"
        echo -e "${BOLD}${WHITE}  [ 6 ]${RESET} ${CYAN}Logs do Sistema${RESET}       - SSH e Xray"
        echo ""
        echo -e "${BOLD}${WHITE}  [ 0 ]${RESET} ${RED}Sair do Painel${RESET}"
        echo ""
        linha_dupla

        ler_input "  Escolha uma opção" "" opcao

        case "$opcao" in
            1) menu_ssh ;;
            2) menu_xray ;;
            3) menu_info ;;
            4) menu_monitor ;;
            5) menu_utils ;;
            6) menu_logs ;;
            0)
                clear
                echo -e "${GREEN}${BOLD}👋 Até logo!${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}Opção inválida!${RESET}"
                sleep 1
                ;;
        esac
    done
}
