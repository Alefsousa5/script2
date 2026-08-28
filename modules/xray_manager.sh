# ============================================================================
# MÓDULO DE GERENCIAMENTO XRAY
# ============================================================================

# Estrutura do config.json básico que o painel usa:
# Usa um inbound "vless" na porta padrão, um "vmess", um "trojan", com um "socks"
# e um outbound freedom. Este módulo cria clientes por email adição em clients.

XRAY_CONFIG_DNS='{
  "servers": ["1.1.1.1", "8.8.8.8", "localhost"]
}'

menu_xray() {
    while true; do
        banner_init
        echo -e "${BG_MAGENTA}${BOLD}${WHITE}        ⚡ MENU XRAY                                    ${RESET}"
        echo ""
        if [ "$XRAY_INSTALADO" -eq 0 ]; then
            echo -e "${YELLOW}  Xray não parece estar instalado.${RESET}"
            echo ""
            echo -e "${BOLD}${WHITE}  [ 1 ]${RESET} Instalar Xray (script oficial)"
            echo -e "${BOLD}${WHITE}  [ 2 ]${RESET} Instalar Xray com configuração básica (recomendado)"
            echo ""
            echo -e "${BOLD}${WHITE}  [ 0 ]${RESET} Voltar"
            echo ""
            linha_dupla
            ler_input "Escolha" "" op
            case "$op" in
                1) xray_instalar_official ;;
                2) xray_instalar_basico ;;
                0) return ;;
                *) echo -e "${RED}Inválido!${RESET}"; sleep 1 ;;
            esac
            continue
        fi

        echo -e "${BOLD}${WHITE}  [ 1 ]${RESET} Criar conta VLESS"
        echo -e "${BOLD}${WHITE}  [ 2 ]${RESET} Criar conta VMess"
        echo -e "${BOLD}${WHITE}  [ 3 ]${RESET} Criar conta Trojan"
        echo -e "${BOLD}${WHITE}  [ 4 ]${RESET} Listar todas as contas"
        echo -e "${BOLD}${WHITE}  [ 5 ]${RESET} Remover conta"
        echo -e "${BOLD}${WHITE}  [ 6 ]${RESET} Exibir link/QRCode de uma conta"
        echo -e "${BOLD}${WHITE}  [ 7 ]${RESET} Reiniciar Xray"
        echo -e "${BOLD}${WHITE}  [ 8 ]${RESET} Parar Xray"
        echo -e "${BOLD}${WHITE}  [ 9 ]${RESET} Status e portas do Xray"
        echo -e "${BOLD}${WHITE}  [10 ]${RESET} Reinstalar/Atualizar Xray"
        echo -e "${BOLD}${WHITE}  [11 ]${RESET} Backup/Restaurar config"
        echo ""
        echo -e "${BOLD}${WHITE}  [ 0 ]${RESET} Voltar"
        echo ""
        linha_dupla

        ler_input "  Escolha" "" op
        case "$op" in
            1) xray_criar_cliente "vless" ;;
            2) xray_criar_cliente "vmess" ;;
            3) xray_criar_cliente "trojan" ;;
            4) xray_listar_contas ;;
            5) xray_remover_conta ;;
            6) xray_mostrar_link ;;
            7) xray_reiniciar ;;
            8) xray_parar ;;
            9) xray_status ;;
            10) xray_instalar_official ;;
            11) xray_backup_menu ;;
            0) return ;;
            *) echo -e "${RED}Inválido!${RESET}"; sleep 1 ;;
        esac
    done
}

# Instalação via script oficial
xray_instalar_official() {
    clear
    linha
    echo -e "${BOLD}INSTALANDO XRAY (oficial)${RESET}"
    linha
    info "Baixando e executando instalador oficial..."
    if bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install; then
        sucesso "Xray instalado."
        XRAY_INSTALADO=1
    else
        error "Falha na instalação."
    fi
    pause
}

# Instalação com configuração básica
xray_instalar_basico() {
    clear
    linha
    echo -e "${BOLD}INSTALAÇÃO XRAY COM CONFIGURAÇÃO BÁSICA${RESET}"
    linha

    # Instala binário
    info "Instalando binário do Xray..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1 || {
        error "Falha ao instalar Xray."; pause; return;
    }

    mkdir -p "$XRAY_DIR"

    # Perguntas de porta
    ler_input "Porta VLESS" "443" port_vless
    ler_input "Porta VMess" "8080" port_vmess
    ler_input "Porta Trojan" "2083" port_trojan

    # Criar certificado auto-assinado (para TLS REALITY-style fallback) ou usar self-signed
    CERT_FILE="$XRAY_DIR/server.crt"
    KEY_FILE="$XRAY_DIR/server.key"
    if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
        info "Gerando certificado auto-assinado..."
        openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
            -keyout "$KEY_FILE" -out "$CERT_FILE" \
            -subj "/C=BR/ST=RJ/L=Rio/O=Painel/CN=example.com" >/dev/null 2>&1
    fi

    # Chaves short-id para VLESS Reality (opcional) - usamos TLS normal neste setup básico
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
      "settings": {
        "clients": [],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
          ]
        }
      },
      "tag": "vless-in",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "port": $port_vmess,
      "protocol": "vmess",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "tcp"
      },
      "tag": "vmess-in",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "port": $port_trojan,
      "protocol": "trojan",
      "settings": {
        "clients": []
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "$CERT_FILE",
              "keyFile": "$KEY_FILE"
            }
          ]
        }
      },
      "tag": "trojan-in",
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
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
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": []
  }
}
EOF

    mkdir -p /var/log/xray
    systemctl enable xray >/dev/null 2>&1
    if systemctl restart xray; then
        XRAY_INSTALADO=1
        sucesso "Xray instalado e configurado!"
        echo ""
        info "Portas abertas: VLESS=$port_vless  VMess=$port_vmess  Trojan=$port_trojan"
        warn "Lembre-se de liberar as portas no firewall (ufw/iptables)."
    else
        error "Falha ao iniciar Xray. Verifique o log."
    fi
    echo "[$(date)] Xray instalado com configuração básica" >> "$PAINEL_LOG"
    pause
}

# Cria cliente genérico
xray_criar_cliente() {
    local proto="$1"
    clear
    linha
    echo -e "${BOLD}CRIAR CONTA $(echo $proto | tr '[:lower:]' '[:upper:]')${RESET}"
    linha

    if [ ! -f "$XRAY_CONFIG" ]; then
        error "Arquivo de configuração do Xray não encontrado: $XRAY_CONFIG"
        echo "Use a opção de instalação básica primeiro."
        pause
        return
    fi

    ler_input "Nome/email do cliente (ex: joao-tim)" "" email
    if [ -z "$email" ]; then
        error "Nome não pode ser vazio!"
        pause
        return
    fi

    # Checar duplicatas
    if jq -r ".inbounds[] | select(.tag==\"$proto-in\") | .settings.clients[].id // .settings.clients[].password // empty" "$XRAY_CONFIG" 2>/dev/null | grep -q "^$email$"; then
        # Checa por password/email
        :
    fi
    if jq -e ".inbounds[] | select(.tag==\"$proto-in\") | .settings.clients[] | select(.email==\"$email\")" "$XRAY_CONFIG" >/dev/null 2>&1; then
        error "Já existe uma conta com esse nome!"
        pause
        return
    fi

    local uuid=""
    local senha_trojan=""
    if [ "$proto" = "trojan" ]; then
        senha_trojan=$(gerar_senha 16)
    else
        uuid=$(gerar_uuid)
    fi

    # Limite de dias
    ler_input "Validade em dias (0 = sem expiração)" "0" dias
    local expira=""
    if [ "$dias" -gt 0 ] 2>/dev/null; then
        expira=$(date -d "+$dias days" +%Y-%m-%d)
    fi

    # Ler comentário (operadora)
    ler_input "Operadora/etiqueta (TIM/Vivo/Claro/etc)" "TIM" etiqueta

    # Backup
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

    # Montar cliente
    local cliente_json
    if [ "$proto" = "trojan" ]; then
        cliente_json="{\"password\":\"$senha_trojan\",\"email\":\"$email\",\"etiqueta\":\"$etiqueta\",\"expira\":\"$expira\"}"
    else
        cliente_json="{\"id\":\"$uuid\",\"email\":\"$email\",\"etiqueta\":\"$etiqueta\",\"expira\":\"$expira\"}"
    fi

    # Inserir no inbound correto
    tmp=$(mktemp)
    jq --argjson c "$cliente_json" --arg tag "$proto-in" '
        .inbounds |= map(if .tag == $tag then .settings.clients += [$c] else . end)
    ' "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

    if ! xray run -test -config "$XRAY_CONFIG" >/dev/null 2>&1; then
        error "Configuração inválida! Revertendo backup..."
        cp "${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)" "$XRAY_CONFIG" 2>/dev/null
        # Tentar pelo backup mais recente
        local bak
        bak=$(ls -t ${XRAY_CONFIG}.bak.* 2>/dev/null | head -1)
        [ -n "$bak" ] && cp "$bak" "$XRAY_CONFIG"
        pause
        return
    fi

    systemctl restart xray
    if ! systemctl is-active --quiet xray; then
        error "Xray não iniciou após criar conta. Verifique os logs."
        pause
        return
    fi

    sucesso "Conta $email criada!"
    echo ""
    xray_exibir_dados "$proto" "$email"
    echo "[$(date)] Criada conta $proto: $email" >> "$PAINEL_LOG"
    pause
}

# Listar todas as contas
xray_listar_contas() {
    clear
    linha
    echo -e "${BOLD}CONTAS XRAY CADASTRADAS${RESET}"
    linha
    if [ ! -f "$XRAY_CONFIG" ]; then
        error "Config não encontrada."
        pause; return
    fi
    local ip
    ip=$(get_ip_publico)
    printf "${BOLD}%-20s %-8s %-12s %-12s %-40s${RESET}\n" "NOME" "PROTOCOLO" "ETIQUETA" "EXPIRA" "UUID/SENHA"
    linha

    for proto in vless vmess trojan; do
        local porta
        porta=$(jq -r ".inbounds[] | select(.tag==\"$proto-in\") | .port" "$XRAY_CONFIG" 2>/dev/null)
        [ -z "$porta" ] && continue
        while IFS=$'\t' read -r email id pass etiqueta expira; do
            local cred=""
            [ -n "$id" ] && cred="$id"
            [ -n "$pass" ] && cred="$pass"
            local cred_curta="${cred:0:20}..."
            local exp_cor="$GREEN"
            if [ -n "$expira" ]; then
                # Verificar se expirou
                exp_ts=$(date -d "$expira" +%s 2>/dev/null)
                now_ts=$(date +%s)
                if [ "$exp_ts" -lt "$now_ts" ]; then
                    exp_cor="$RED"
                else
                    exp_cor="$YELLOW"
                fi
            fi
            printf "%-20s ${CYAN}%-8s${RESET} %-12s ${exp_cor}%-12s${RESET} %-40s\n" "$email" "${proto^^}" "${etiqueta:--}" "${expira:-Nunca}" "$cred_curta"
        done < <(jq -r ".inbounds[] | select(.tag==\"$proto-in\") | .settings.clients[] | [.email, (.id // \"\"), (.password // \"\"), (.etiqueta // \"\"), (.expira // \"\")] | @tsv" "$XRAY_CONFIG" 2>/dev/null)
    done
    echo ""
    linha
    info "Use a opção 6 para ver link/QRCode de uma conta."
    pause
}

# Remover conta
xray_remover_conta() {
    clear
    linha
    echo -e "${BOLD}REMOVER CONTA XRAY${RESET}"
    linha
    ler_input "Nome/email da conta" "" email
    [ -z "$email" ] && return
    cp "$XRAY_CONFIG" "${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    tmp=$(mktemp)
    jq --arg e "$email" '
        .inbounds |= map(.settings.clients = ((.settings.clients // []) | map(select(.email != $e))))
    ' "$XRAY_CONFIG" > "$tmp" && mv "$tmp" "$XRAY_CONFIG"

    xray run -test -config "$XRAY_CONFIG" >/dev/null 2>&1 && {
        systemctl restart xray
        sucesso "Conta $email removida!"
    } || {
        error "Config inválida após remoção. Restaurando backup."
        cp "${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)" "$XRAY_CONFIG"
    }
    echo "[$(date)] Removida conta Xray: $email" >> "$PAINEL_LOG"
    pause
}

# Mostrar link/QRCode
xray_mostrar_link() {
    clear
    linha
    echo -e "${BOLD}EXIBIR LINK E QR CODE${RESET}"
    linha
    ler_input "Nome/email da conta" "" email
    [ -z "$email" ] && return
    # Determinar protocolo
    for proto in vless vmess trojan; do
        if jq -e ".inbounds[] | select(.tag==\"$proto-in\") | .settings.clients[] | select(.email==\"$email\")" "$XRAY_CONFIG" >/dev/null 2>&1; then
            xray_exibir_dados "$proto" "$email"
            pause
            return
        fi
    done
    error "Conta não encontrada."
    pause
}

# Exibe dados (link e QR) de uma conta
xray_exibir_dados() {
    local proto="$1"
    local email="$2"
    local ip
    ip=$(get_ip_publico)
    local porta
    porta=$(jq -r ".inbounds[] | select(.tag==\"$proto-in\") | .port" "$XRAY_CONFIG")
    local tls
    tls=$(jq -r ".inbounds[] | select(.tag==\"$proto-in\") | .streamSettings.security // \"none\"" "$XRAY_CONFIG")
    local network
    network=$(jq -r ".inbounds[] | select(.tag==\"$proto-in\") | .streamSettings.network // \"tcp\"" "$XRAY_CONFIG")

    local link=""
    local id=""
    local pass=""
    local add="$ip"
    local ps="$email"

    if [ "$proto" = "vless" ]; then
        id=$(jq -r ".inbounds[] | select(.tag==\"$proto-in\") | .settings.clients[] | select(.email==\"$email\") | .id" "$XRAY_CONFIG")
        # security: se inbound tiver tls, usa tls
        local sec="none"
        [ "$tls" = "tls" ] && sec="tls"
        link="vless://${id}@${add}:${porta}?security=${sec}&encryption=none&type=${network}&sni=${ip}#${ps}"
    elif [ "$proto" = "vmess" ]; then
        id=$(jq -r ".inbounds[] | select(.tag==\"$proto-in\") | .settings.clients[] | select(.email==\"$email\") | .id" "$XRAY_CONFIG")
        local json_vmess
        json_vmess=$(jq -n --arg v "$id" --arg add "$add" --arg port "$porta" --arg ps "$ps" \
            '{v:"2",ps:$ps,add:$add,port:$port,id:$v,aid:"0",scy:"auto",net:"tcp",type:"none",host:"",path:"",tls:""}')
        if [ "$tls" = "tls" ]; then
            json_vmess=$(echo "$json_vmess" | jq '.tls="tls"')
        fi
        local encoded
        encoded=$(echo "$json_vmess" | base64 -w0)
        link="vmess://${encoded}"
    elif [ "$proto" = "trojan" ]; then
        pass=$(jq -r ".inbounds[] | select(.tag==\"$proto-in\") | .settings.clients[] | select(.email==\"$email\") | .password" "$XRAY_CONFIG")
        local sec="none"
        [ "$tls" = "tls" ] && sec="tls"
        link="trojan://${pass}@${add}:${porta}?security=${sec}&type=${network}#${ps}"
    fi

    echo -e "${YELLOW}📱 Link de conexão (${proto^^}):${RESET}"
    linha
    echo -e "${GREEN}$link${RESET}"
    linha
    echo ""

    if command -v qrencode &>/dev/null; then
        echo -e "${YELLOW}📷 QR Code (escaneie no app):${RESET}"
        echo ""
        qrencode -t ANSIUTF8 "$link"
        echo ""
    else
        warn "qrencode não instalado. Instale com: apt install qrencode"
    fi
}

# Reiniciar Xray
xray_reiniciar() {
    clear
    linha
    echo -e "${BOLD}REINICIAR XRAY${RESET}"
    linha
    if xray run -test -config "$XRAY_CONFIG" >/tmp/xray-test.txt 2>&1; then
        systemctl restart xray && sucesso "Xray reiniciado!" || error "Falha."
    else
        error "Configuração inválida!"
        cat /tmp/xray-test.txt
    fi
    pause
}

# Parar Xray
xray_parar() {
    clear
    systemctl stop xray && warn "Xray parado."
    pause
}

# Status
xray_status() {
    clear
    linha
    echo -e "${BOLD}STATUS DO XRAY${RESET}"
    linha
    systemctl status xray --no-pager 2>&1 | head -20
    echo ""
    linha
    echo -e "${BOLD}PORTAS EM USO:${RESET}"
    if [ -f "$XRAY_CONFIG" ]; then
        for proto in vless vmess trojan; do
            porta=$(jq -r ".inbounds[] | select(.tag==\"$proto-in\") | .port" "$XRAY_CONFIG" 2>/dev/null)
            if [ -n "$porta" ]; then
                echo "  ${CYAN}${proto^^}${RESET}: porta $porta"
            fi
        done
    fi
    echo ""
    # Processos
    echo -e "${BOLD}CONEXÕES ATIVAS:${RESET}"
    if [ -f /var/log/xray/access.log ]; then
        echo "$(wc -l < /var/log/xray/access.log) linhas no access.log"
    fi
    ss -tnp 2>/dev/null | grep xray | head -10 || echo "Nenhuma conexão detectada."
    pause
}

# Backup menu
xray_backup_menu() {
    clear
    linha
    echo -e "${BOLD}BACKUP E RESTAURAÇÃO DA CONFIG XRAY${RESET}"
    linha
    echo "1 - Fazer backup da config atual"
    echo "2 - Restaurar backup mais recente"
    echo "3 - Listar backups"
    echo "0 - Voltar"
    ler_input "Opção" "" op
    case "$op" in
        1)
            local bkp="${XRAY_CONFIG}.backup.$(date +%Y%m%d-%H%M%S).json"
            cp "$XRAY_CONFIG" "$bkp"
            sucesso "Backup salvo em $bkp"
            ;;
        2)
            local bkp
            bkp=$(ls -t ${XRAY_CONFIG}.backup.*.json 2>/dev/null | head -1)
            [ -z "$bkp" ] && { error "Nenhum backup encontrado."; pause; return; }
            cp "$bkp" "$XRAY_CONFIG"
            systemctl restart xray && sucesso "Restaurado de $bkp" || error "Falha ao reiniciar"
            ;;
        3)
            ls -lh ${XRAY_CONFIG}.backup.*.json 2>/dev/null || echo "Sem backups."
            ls -lh ${XRAY_CONFIG}.bak.* 2>/dev/null | tail -20
            ;;
    esac
    pause
}
