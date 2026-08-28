# ============================================================================
# MÓDULO DE INFORMAÇÕES DO SISTEMA
# ============================================================================

menu_info() {
    clear
    banner_init
    echo -e "${BG_GREEN}${BOLD}${WHITE}        💻 INFORMAÇÕES DO SISTEMA                       ${RESET}"
    echo ""

    # S.O.
    local os=""
    [ -f /etc/os-release ] && os=$(. /etc/os-release && echo "$PRETTY_NAME")
    [ -z "$os" ] && os=$(uname -a)
    echo -e "${BOLD}  Sistema Operacional:${RESET}   $os"

    # Kernel
    echo -e "${BOLD}  Kernel:${RESET}                $(uname -r)"

    # Arquitetura
    echo -e "${BOLD}  Arquitetura:${RESET}          $(uname -m)"

    # Hostname
    echo -e "${BOLD}  Hostname:${RESET}             $(hostname)"

    # IP público
    echo -e "${BOLD}  IP Público:${RESET}           $(get_ip_publico)"

    # IP privado
    local ip_priv
    ip_priv=$(ip -4 addr show scope global 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1)
    echo -e "${BOLD}  IP Privado:${RESET}           ${ip_priv:-N/A}"

    # Uptime
    echo -e "${BOLD}  Uptime:${RESET}               $(uptime -p 2>/dev/null | sed 's/up //')"

    # CPU
    echo ""
    linha
    echo -e "${BOLD}  CPU:${RESET}"
    local cpu_model
    cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//')
    local cpu_cores
    cpu_cores=$(nproc)
    echo -e "    Modelo: $cpu_model"
    echo -e "    Núcleos: $cpu_cores"
    # Uso CPU
    local cpu_uso
    cpu_uso=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}')
    echo -e "    Uso atual: ${cpu_uso}%"

    # RAM
    echo ""
    linha
    echo -e "${BOLD}  MEMÓRIA RAM:${RESET}"
    free -h | awk '/Mem:/ {printf "    Total: %s | Usado: %s | Livre: %s\n", $2, $3, $7}'
    # Swap
    free -h | awk '/Swap:/ {printf "    Swap  - Total: %s | Usado: %s | Livre: %s\n", $2, $3, $4}'

    # Disco
    echo ""
    linha
    echo -e "${BOLD}  DISCO (/):${RESET}"
    df -h / | awk 'NR==2 {printf "    Total: %s | Usado: %s | Disponível: %s | Uso: %s\n", $2, $3, $4, $5}'

    # Rede/Tráfego
    echo ""
    linha
    echo -e "${BOLD}  INTERFACES DE REDE:${RESET}"
    ip -br addr 2>/dev/null | head -10 || ifconfig | head -30

    echo ""
    linha
    echo -e "${BOLD}  TRÁFEGO DE REDE (total desde o boot):${RESET}"
    if [ -f /proc/net/dev ]; then
        local rx=0 tx=0
        while read -r iface r _; do
            [[ "$iface" == lo:* ]] && continue
            [[ "$iface" != *:* ]] && continue
            local rb
            rb=$(echo "$r" | awk '{print $2}')
            local tb
            tb=$(echo "$r" | awk '{print $10}')
            rx=$((rx + rb))
            tx=$((tx + tb))
        done < /proc/net/dev
        echo "    Download: $(numfmt --to=iec-i --suffix=B $rx)"
        echo "    Upload:   $(numfmt --to=iec-i --suffix=B $tx)"
    fi

    # Carga
    echo ""
    linha
    echo -e "${BOLD}  CARGA DO SISTEMA (load average):${RESET} $(cat /proc/loadavg | awk '{print $1, $2, $3}')"

    # Serviços importantes
    echo ""
    linha
    echo -e "${BOLD}  SERVIÇOS:${RESET}"
    for svc in sshd ssh xray nginx apache2 openvpn wg-quick@wg0 fail2ban ufw; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "    ${GREEN}●${RESET} $svc"
        elif systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "^${svc}"; then
            echo -e "    ${RED}●${RESET} $svc (parado)"
        fi
    done

    echo ""
    linha_dupla
    pause
}
