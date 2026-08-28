# ============================================================================
# MÓDULO DE GERENCIAMENTO SSH
# ============================================================================

menu_ssh() {
    while true; do
        banner_init
        echo -e "${BG_CYAN}${BOLD}${WHITE}        🛡️  MENU SSH                                   ${RESET}"
        echo ""
        echo -e "${BOLD}${WHITE}  [ 1 ]${RESET} Criar novo usuário SSH"
        echo -e "${BOLD}${WHITE}  [ 2 ]${RESET} Listar usuários SSH"
        echo -e "${BOLD}${WHITE}  [ 3 ]${RESET} Alterar senha de usuário"
        echo -e "${BOLD}${WHITE}  [ 4 ]${RESET} Remover usuário SSH"
        echo -e "${BOLD}${WHITE}  [ 5 ]${RESET} Limitar acesso (expiração de conta)"
        echo -e "${BOLD}${WHITE}  [ 6 ]${RESET} Alterar porta do SSH"
        echo -e "${BOLD}${WHITE}  [ 7 ]${RESET} Bloquear/Desbloquear usuário"
        echo -e "${BOLD}${WHITE}  [ 8 ]${RESET} Desabilitar login root por senha"
        echo -e "${BOLD}${WHITE}  [ 9 ]${RESET} Reiniciar serviço SSH"
        echo -e "${BOLD}${WHITE}  [10 ]${RESET} Gerar chave SSH para usuário"
        echo ""
        echo -e "${BOLD}${WHITE}  [ 0 ]${RESET} Voltar ao menu principal"
        echo ""
        linha_dupla

        ler_input "  Escolha" "" op
        case "$op" in
            1) ssh_criar_usuario ;;
            2) ssh_listar_usuarios ;;
            3) ssh_alterar_senha ;;
            4) ssh_remover_usuario ;;
            5) ssh_limitar_expiracao ;;
            6) ssh_alterar_porta ;;
            7) ssh_bloquear_desbloquear ;;
            8) ssh_desabilitar_root_senha ;;
            9) ssh_reiniciar ;;
            10) ssh_gerar_chave ;;
            0) return ;;
            *) echo -e "${RED}Opção inválida!${RESET}"; sleep 1 ;;
        esac
    done
}

# Criação de usuário SSH
ssh_criar_usuario() {
    clear
    linha
    echo -e "${BOLD}CRIAR NOVO USUÁRIO SSH${RESET}"
    linha
    ler_input "Nome de usuário" "" usuario
    if id "$usuario" &>/dev/null; then
        error "Usuário $usuario já existe!"
        pause
        return
    fi
    ler_input "Senha (deixe em branco para gerar aleatória)" "" senha
    if [ -z "$senha" ]; then
        senha=$(gerar_senha 14)
        info "Senha gerada: $senha"
    fi
    ler_input "Validade em dias (0 = sem expiração)" "0" dias

    # Cria usuário com shell válido
    useradd -m -s /bin/bash "$usuario"
    echo "$usuario:$senha" | chpasswd
    sucesso "Usuário $usuario criado com sucesso!"

    if [ "$dias" -gt 0 ] 2>/dev/null; then
        chage -E "$(date -d "+$dias days" +%Y-%m-%d)" "$usuario" 2>/dev/null && \
            info "Conta expira em $dias dias."
    fi

    echo ""
    echo -e "${YELLOW}Dados de acesso:${RESET}"
    echo "  Host: $(get_ip_publico)"
    ssh_port=$(grep -E "^Port\s+" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}')
    ssh_port="${ssh_port:-22}"
    echo "  Porta: $ssh_port"
    echo "  Usuário: $usuario"
    echo "  Senha: $senha"
    echo "  Comando: ssh $usuario@$(get_ip_publico) -p $ssh_port"

    # Log
    echo "[$(date)] Criado usuário SSH: $usuario" >> "$PAINEL_LOG"
    pause
}

# Listar usuários
ssh_listar_usuarios() {
    clear
    linha
    echo -e "${BOLD}USUÁRIOS SSH (UID >= 1000)${RESET}"
    linha
    printf "${BOLD}%-15s %-8s %-15s %-12s %s${RESET}\n" "USUÁRIO" "UID" "HOME" "VALIDADE" "SHELL"
    linha

    while IFS=: read -r usuario _ uid _ _ home shell; do
        if [ "$uid" -ge 1000 ] && [ "$uid" -lt 65534 ]; then
            expira=$(chage -l "$usuario" 2>/dev/null | grep "Account expires" | cut -d: -f2 | sed 's/^ *//')
            if [ -z "$expira" ] || [[ "$expira" == *"never"* ]] || [[ "$expira" == *"nunca"* ]]; then
                expira="Nunca"
                expira_cor="$GREEN"
            else
                expira_cor="$YELLOW"
            fi
            printf "%-15s %-8s %-15s ${expira_cor}%-12s${RESET} %s\n" "$usuario" "$uid" "$home" "$expira" "$shell"
        fi
    done < /etc/passwd
    echo ""
    linha
    total=$(awk -F: '$3>=1000 && $3<65534{c++} END{print c+0}' /etc/passwd)
    info "Total de usuários: $total"
    pause
}

# Alterar senha
ssh_alterar_senha() {
    clear
    linha
    echo -e "${BOLD}ALTERAR SENHA DE USUÁRIO${RESET}"
    linha
    ler_input "Nome de usuário" "" usuario
    if ! id "$usuario" &>/dev/null; then
        error "Usuário não existe!"
        pause
        return
    fi
    ler_input "Nova senha (deixe em branco para gerar)" "" senha
    if [ -z "$senha" ]; then
        senha=$(gerar_senha 14)
    fi
    echo "$usuario:$senha" | chpasswd
    sucesso "Senha alterada! Nova senha: $senha"
    echo "[$(date)] Senha alterada: $usuario" >> "$PAINEL_LOG"
    pause
}

# Remover usuário
ssh_remover_usuario() {
    clear
    linha
    echo -e "${BOLD}REMOVER USUÁRIO SSH${RESET}"
    linha
    ler_input "Nome de usuário a remover" "" usuario
    if [ "$usuario" = "root" ]; then
        error "Não é possível remover o usuário root!"
        pause
        return
    fi
    if ! id "$usuario" &>/dev/null; then
        error "Usuário não existe!"
        pause
        return
    fi
    ler_input "Remover também o diretório home? (s/n)" "n" rem_home
    if [ "$rem_home" = "s" ] || [ "$rem_home" = "S" ]; then
        userdel -r "$usuario"
    else
        userdel "$usuario"
    fi
    sucesso "Usuário $usuario removido!"
    echo "[$(date)] Removido usuário: $usuario" >> "$PAINEL_LOG"
    pause
}

# Expiração de conta
ssh_limitar_expiracao() {
    clear
    linha
    echo -e "${BOLD}LIMITAR VALIDADE DE CONTA${RESET}"
    linha
    ler_input "Usuário" "" usuario
    if ! id "$usuario" &>/dev/null; then
        error "Usuário não existe!"
        pause
        return
    fi
    echo "Expiração atual: $(chage -l "$usuario" | grep "Account expires" | cut -d: -f2)"
    ler_input "Dias até expirar (0 para remover expiração)" "" dias
    if [ "$dias" = "0" ]; then
        chage -E -1 "$usuario"
        sucesso "Expiração removida!"
    else
        chage -E "$(date -d "+$dias days" +%Y-%m-%d)" "$usuario"
        sucesso "Conta expirará em $dias dias."
    fi
    pause
}

# Alterar porta SSH
ssh_alterar_porta() {
    clear
    linha
    echo -e "${BOLD}ALTERAR PORTA SSH${RESET}"
    linha
    porta_atual=$(grep -E "^Port\s+" "$SSH_CONFIG" 2>/dev/null | awk '{print $2}')
    porta_atual="${porta_atual:-22}"
    info "Porta atual: $porta_atual"
    ler_input "Nova porta" "" nova_porta
    if ! [[ "$nova_porta" =~ ^[0-9]+$ ]] || [ "$nova_porta" -lt 1 ] || [ "$nova_porta" -gt 65535 ]; then
        error "Porta inválida!"
        pause
        return
    fi
    if ! porta_livre "$nova_porta" && [ "$nova_porta" != "$porta_atual" ]; then
        warn "Porta $nova_porta parece estar em uso. Continuar? (s/n)"
        read -r cont
        [ "$cont" != "s" ] && return
    fi

    # Backup
    cp "$SSH_CONFIG" "${SSH_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    if grep -qE "^#?Port\s+" "$SSH_CONFIG"; then
        sed -i "s/^#\?Port\s\+.*/Port $nova_porta/" "$SSH_CONFIG"
    else
        echo "Port $nova_porta" >> "$SSH_CONFIG"
    fi

    # Firewall (ufw/firewalld/iptables)
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw allow "$nova_porta/tcp" >/dev/null 2>&1
        ufw allow "$nova_porta/udp" >/dev/null 2>&1
        info "Porta $nova_porta liberada no UFW"
    fi

    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        sucesso "Porta alterada para $nova_porta! NÃO feche a sessão atual."
        warn "Teste o acesso em outra janela antes de sair!"
    else
        error "Falha ao reiniciar SSH! Verifique a configuração."
    fi
    echo "[$(date)] Porta SSH alterada para $nova_porta" >> "$PAINEL_LOG"
    pause
}

# Bloquear/Desbloquear
ssh_bloquear_desbloquear() {
    clear
    linha
    echo -e "${BOLD}BLOQUEAR/DESBLOQUEAR USUÁRIO${RESET}"
    linha
    ler_input "Usuário" "" usuario
    if ! id "$usuario" &>/dev/null; then
        error "Usuário não existe!"
        pause
        return
    fi
    status=$(passwd -S "$usuario" | awk '{print $2}')
    info "Status atual: $status (L=bloqueado, P=ativo)"
    if [ "$status" = "L" ]; then
        ler_input "Desbloquear usuário? (s/n)" "s" acao
        if [ "$acao" = "s" ]; then
            passwd -u "$usuario" && sucesso "Usuário desbloqueado!"
        fi
    else
        ler_input "Bloquear usuário? (s/n)" "s" acao
        if [ "$acao" = "s" ]; then
            passwd -l "$usuario" && sucesso "Usuário bloqueado!"
        fi
    fi
    pause
}

# Desabilitar root por senha
ssh_desabilitar_root_senha() {
    clear
    linha
    echo -e "${BOLD}CONFIGURAÇÕES DE SEGURANÇA - ROOT${RESET}"
    linha
    warn "Recomendado usar chaves SSH antes de desabilitar login por senha do root."
    echo "1 - Permitir login root com senha"
    echo "2 - Proibir login root com senha"
    echo "3 - Proibir login root completamente"
    ler_input "Opção" "" op
    cp "$SSH_CONFIG" "${SSH_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    case "$op" in
        1)
            sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
            ;;
        2)
            sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSH_CONFIG"
            ;;
        3)
            sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSH_CONFIG"
            ;;
        *) return ;;
    esac
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
    sucesso "Configuração aplicada!"
    pause
}

# Reiniciar SSH
ssh_reiniciar() {
    clear
    linha
    echo -e "${BOLD}REINICIAR SSH${RESET}"
    linha
    if systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null; then
        sucesso "SSH reiniciado com sucesso!"
    else
        error "Falha ao reiniciar SSH"
    fi
    pause
}

# Gerar chave SSH para usuário
ssh_gerar_chave() {
    clear
    linha
    echo -e "${BOLD}GERAR PAR DE CHAVES SSH${RESET}"
    linha
    ler_input "Nome de usuário" "" usuario
    if ! id "$usuario" &>/dev/null; then
        error "Usuário não existe!"
        pause
        return
    fi
    user_home=$(eval echo "~$usuario")
    mkdir -p "$user_home/.ssh"
    chmod 700 "$user_home/.ssh"

    # Gera chave ed25519
    ssh-keygen -t ed25519 -f "$user_home/.ssh/id_ed25519" -N "" -C "$usuario@$(hostname)" <<<y >/dev/null 2>&1

    # Adiciona a chave pública como autorizada
    cat "$user_home/.ssh/id_ed25519.pub" >> "$user_home/.ssh/authorized_keys"
    chmod 600 "$user_home/.ssh/authorized_keys"
    chmod 600 "$user_home/.ssh/id_ed25519"
    chmod 644 "$user_home/.ssh/id_ed25519.pub"
    chown -R "$usuario:$usuario" "$user_home/.ssh"

    sucesso "Par de chaves gerado!"
    echo ""
    echo -e "${YELLOW}Chave PRIVADA (salve-a com cuidado):${RESET}"
    linha
    cat "$user_home/.ssh/id_ed25519"
    linha
    echo ""
    warn "Você pode copiar a chave privada acima para acessar sem senha."
    pause
}
