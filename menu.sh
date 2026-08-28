#!/usr/bin/env bash
#
# menu.sh — Menu de gerenciamento do Xray na VPS.
#
# Uso:
#   sudo xray-menu            # abre o menu interativo
#   sudo bash menu.sh         # mesmo que acima
#   sudo xray-menu --enforce  # remove expirados/suspensos e recarrega (cron)
#
set -euo pipefail

XRAY_DIR="/usr/local/etc/xray"
XRAY_CONFIG="$XRAY_DIR/config.json"
XRAY_USERS="$XRAY_DIR/users.json"
XRAY_SETTINGS="$XRAY_DIR/settings.json"
XRAY_BIN="/usr/local/bin/xray"
XRAY_LOG_DIR="/var/log/xray"
XRAY_SERVICE="xray"
DEFAULT_PORT="8080"
DEFAULT_PROTOCOL="vless"

USE_COLOR="1"
if [[ ! -t 1 || "${NO_COLOR:-}" == "1" ]]; then
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
# Requisitos                                                                  #
# --------------------------------------------------------------------------- #
require_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        die "Rodar com sudo: sudo xray-menu (ou sudo bash menu.sh)"
    fi
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

ensure_tools() {
    if ! have_cmd jq; then
        warn "Faltando jq. Instalando..."
        if have_cmd apt-get; then
            DEBIAN_FRONTEND=noninteractive apt-get update -y >/dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install -y jq >/dev/null
        elif have_cmd dnf; then
            dnf install -y jq >/dev/null
        elif have_cmd yum; then
            yum install -y jq >/dev/null
        elif have_cmd apk; then
            apk add jq >/dev/null
        else
            die "Não foi possível instalar o jq. Instale manualmente e rode novamente."
        fi
    fi
    if [[ ! -x "$XRAY_BIN" ]]; then
        die "Xray não encontrado em $XRAY_BIN. Rode primeiro: sudo bash install.sh"
    fi
}

ensure_files() {
    mkdir -p "$XRAY_DIR" "$XRAY_LOG_DIR"

    if [[ ! -f "$XRAY_SETTINGS" ]]; then
        local port="$DEFAULT_PORT"
        local proto="$DEFAULT_PROTOCOL"

        # Tenta reaproveitar a primeira porta/protocolo da config existente.
        if [[ -f "$XRAY_CONFIG" ]]; then
            port="$(jq -r '.inbounds[0].port // 8080' "$XRAY_CONFIG" 2>/dev/null || echo "$DEFAULT_PORT")"
            proto="$(jq -r '.inbounds[0].protocol // "vless"' "$XRAY_CONFIG" 2>/dev/null || echo "$DEFAULT_PROTOCOL")"
        fi

        cat > "$XRAY_SETTINGS" <<EOF
{
  "protocol": "$proto",
  "main_port": $port,
  "ports": [
    {"port": $port, "network": "tcp"},
    {"port": $((port + 1)), "network": "kcp"}
  ]
}
EOF
    fi

    if [[ ! -f "$XRAY_USERS" ]]; then
        echo "[]" > "$XRAY_USERS"
    fi

    chown -R xray:xray "$XRAY_DIR" 2>/dev/null || true
    chmod 600 "$XRAY_SETTINGS" "$XRAY_USERS" 2>/dev/null || true
}

# --------------------------------------------------------------------------- #
# Helpers de JSON                                                             #
# --------------------------------------------------------------------------- #
user_count() {
    jq 'length' "$XRAY_USERS"
}

today() {
    date +%F
}

validate_user_name() {
    if [[ ! "$1" =~ ^[a-zA-Z0-9_]{3,32}$ ]]; then
        die "Nome inválido: use 3-32 caracteres (letras, números, _)."
    fi
    if jq -e --arg n "$1" 'any(.[]; .name == $n)' "$XRAY_USERS" >/dev/null 2>&1; then
        die "Já existe um usuário chamado '$1'."
    fi
}

validate_date() {
    local d="$1"
    if [[ -z "$d" ]]; then return 0; fi
    if ! [[ "$d" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        die "Data inválida: use o formato YYYY-MM-DD (ex.: 2026-12-31)."
    fi
    if ! date -d "$d" >/dev/null 2>&1; then
        die "Data inválida: $d"
    fi
}

validate_port() {
    local pnum
    for pnum in "$@"; do
        if ! [[ "$pnum" =~ ^[0-9]+$ ]] || (( pnum < 1 || pnum > 65535 )); then
            die "Porta inválida: $pnum"
        fi
        if jq -e --argjson p "$pnum" 'any(.ports[]; .port == $p)' "$XRAY_SETTINGS" >/dev/null 2>&1; then
            die "A porta $pnum já está cadastrada."
        fi
    done
}

generate_uuid() {
    local u
    if [[ -f /proc/sys/kernel/random/uuid ]]; then
        cat /proc/sys/kernel/random/uuid
    elif have_cmd openssl; then
        openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
    elif have_cmd python3; then
        python3 -c 'import uuid; print(uuid.uuid4())'
    else
        die "Não consegui gerar UUID."
    fi
}

# --------------------------------------------------------------------------- #
# Geração da config do Xray                                                   #
# --------------------------------------------------------------------------- #
JQ_PROG='
def active_users($today):
  map(select(
    (.suspended == false)
    and ((.expiry == null or .expiry == "") or (.expiry >= $today))
  ));

($settings[0] // {}) as $s
| ($users[0] // []) as $u
| (($s.ports // []) | length) as $ports_len
| ($u | active_users($today)) as $active
| {
    log: {
      loglevel: "warning",
      access: $access_log,
      error: $error_log
    },
    inbounds: [
      (if $ports_len > 0 then $s.ports else [
        {"port": ($s.main_port // 8080), "network": "tcp"},
        {"port": (($s.main_port // 8080) + 1), "network": "kcp"}
      ] end)[] |
      {
        port: .port,
        listen: "0.0.0.0",
        protocol: ($s.protocol // "vless"),
        settings: (if ($s.protocol // "vless") == "vless" then
          {clients: ($active | map({id: .uuid, email: (.name + "@xray")})), decryption: "none"}
          else
          {clients: ($active | map({id: .uuid, email: (.name + "@xray")}))}
          end),
        streamSettings: ({network: .network, security: (.security // "none")}
          + (if .network == "kcp" then
              {kcpSettings: {mtu: 1350, tti: 50, uplinkCapacity: 5, downlinkCapacity: 20, congestion: false, readBufferSize: 1, writeBufferSize: 1, header: {type: "none"}}}
            else {} end)),
        tag: ("inbound-" + .network + "-" + (.port|tostring))
      }
    ],
    outbounds: [
      {"protocol": "freedom", "settings": {}, "tag": "direct"},
      {"protocol": "blackhole", "settings": {}, "tag": "blocked"}
    ]
  }
  + (if $has_geo == "1" then {
      routing: {
        rules: [
          {"type": "field", "ip": ["geoip:private"], "outboundTag": "blocked"}
        ]
      }
    } else {} end)
'

build_config() {
    local tmp has_geo
    tmp="$XRAY_CONFIG.tmp"
    has_geo="0"
    [[ -f "$XRAY_DIR/geoip.dat" ]] && has_geo="1"

    if ! jq -n \
        --arg today "$(today)" \
        --arg has_geo "$has_geo" \
        --arg access_log "$XRAY_LOG_DIR/access.log" \
        --arg error_log "$XRAY_LOG_DIR/error.log" \
        --slurpfile users "$XRAY_USERS" \
        --slurpfile settings "$XRAY_SETTINGS" \
        "$JQ_PROG" > "$tmp"; then
        rm -f "$tmp"
        error "Falha ao gerar a configuração do Xray."
        return 1
    fi

    if ! "$XRAY_BIN" run -test -config "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        error "A configuração gerada é inválida. Nada foi aplicado."
        return 1
    fi

    if [[ -f "$XRAY_CONFIG" ]] && cmp -s "$tmp" "$XRAY_CONFIG"; then
        rm -f "$tmp"
        return 0
    fi

    mv "$tmp" "$XRAY_CONFIG"
    chown xray:xray "$XRAY_CONFIG"
    chmod 600 "$XRAY_CONFIG"

    systemctl restart "$XRAY_SERVICE" >/dev/null 2>&1 || {
        error "Falha ao reiniciar o xray. Veja: journalctl -u xray -e"
        return 1
    }

    info "Configuração aplicada e Xray reiniciado."
}

apply_config() {
    if ! build_config; then
        return 1
    fi
    return 0
}

# --------------------------------------------------------------------------- #
# Enforce: remove expirados/suspensos da config                              #
# --------------------------------------------------------------------------- #
enforce() {
    apply_config || true
    info "Verificação de expirados/suspensos aplicada."
}

# --------------------------------------------------------------------------- #
# Listagem                                                                     #
# --------------------------------------------------------------------------- #
list_users() {
    local count
    count="$(user_count)"
    if [[ "$count" -eq 0 ]]; then
        echo "   Nenhum usuário cadastrado."
        return 1
    fi

    printf '\n'
    printf '%-4s %-18s %-38s %-12s %-10s %-10s\n' "Nº" "Nome" "UUID" "Validade" "Limite" "Status"
    printf '%s\n' "----------------------------------------------------------------------------------------"
    jq -r 'to_entries[] |
        (.key + 1), .value.name, .value.uuid, (.value.expiry // "-"), ((.value.limit_gb|tostring) + " GB"), (if .value.suspended then "SUSPENSO" else "ativo" end)' \
        "$XRAY_USERS" 2>/dev/null | paste -d" " - - - - - - | nl -ba -w2 -s'  '
    printf '\n'
}

list_portas() {
    printf '\n'
    printf '%-4s %-10s %-10s\n' "Nº" "Porta" "Rede"
    printf '%s\n' "-----------------------"
    jq -r '.ports[] | [.port, .network] | @tsv' "$XRAY_SETTINGS" | column -t -s$'\t' | nl -ba -w2 -s'  '
    printf '\n'
}

select_user() {
    local idx choice
    list_users || true
    read -rp "Número do usuário: " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > $(user_count) )); then
        die "Seleção inválida: $choice"
    fi
    echo "${choice}"
}

# --------------------------------------------------------------------------- #
# Criar usuário                                                                 #
# --------------------------------------------------------------------------- #
create_user() {
    local name uuid expiry limit today_str
    today_str="$(today)"

    read -rp "Nome do usuário (ex.: tim01): " name
    validate_user_name "$name"

    uuid="$(generate_uuid)"

    read -rp "Data de validade (YYYY-MM-DD, Enter para sem limite): " expiry
    validate_date "$expiry"

    read -rp "Limite em GB (0 = sem limite): " limit
    [[ -z "$limit" ]] && limit="0"
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
        die "Limite inválido: use um número inteiro."
    fi

    jq --arg name "$name" \
       --arg uuid "$uuid" \
       --arg expiry "$expiry" \
       --argjson limit "$limit" \
       --arg today "$today_str" \
       '. + [{name: $name, uuid: $uuid, email: ($name + "@xray"), created: $today, expiry: $expiry, limit_gb: $limit, suspended: false}]' \
       "$XRAY_USERS" > "$XRAY_USERS.tmp"
    mv "$XRAY_USERS.tmp" "$XRAY_USERS"
    chmod 600 "$XRAY_USERS"

    info "Usuário '$name' criado."
    printf '    UUID   : %s\n' "$uuid"
    printf '    Validade: %s\n' "${expiry:-sem limite}"
    printf '    Limite : %s GB\n' "$limit"

    apply_config
}

# --------------------------------------------------------------------------- #
# Data / validade                                                               #
# --------------------------------------------------------------------------- #
manage_date() {
    local idx name expiry today_str
    today_str="$(today)"
    idx="$(select_user)"
    name="$(jq -r ".[$idx - 1].name" "$XRAY_USERS")"

    echo ""
    info "Editando validade do usuário '$name' (hoje: $today_str)."
    read -rp "Nova validade (YYYY-MM-DD, Enter para remover limite): " expiry
    validate_date "$expiry"

    jq --argjson idx "$((idx - 1))" --arg expiry "$expiry" \
       '.[$idx].expiry = $expiry' "$XRAY_USERS" > "$XRAY_USERS.tmp"
    mv "$XRAY_USERS.tmp" "$XRAY_USERS"
    chmod 600 "$XRAY_USERS"

    info "Validade de '$name' definida para ${expiry:-sem limite}."
    apply_config
}

# --------------------------------------------------------------------------- #
# Limite                                                                        #
# --------------------------------------------------------------------------- #
manage_limit() {
    local idx name limit
    idx="$(select_user)"
    name="$(jq -r ".[$idx - 1].name" "$XRAY_USERS")"

    echo ""
    info "Editando limite do usuário '$name'."
    read -rp "Novo limite em GB (0 = sem limite): " limit
    [[ -z "$limit" ]] && limit="0"
    if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
        die "Limite inválido: use um número inteiro."
    fi

    jq --argjson idx "$((idx - 1))" --argjson limit "$limit" \
       '.[$idx].limit_gb = $limit' "$XRAY_USERS" > "$XRAY_USERS.tmp"
    mv "$XRAY_USERS.tmp" "$XRAY_USERS"
    chmod 600 "$XRAY_USERS"

    info "Limite de '$name' definido para $limit GB."
    apply_config
}

# --------------------------------------------------------------------------- #
# Suspender / reativar                                                        #
# --------------------------------------------------------------------------- #
manage_suspend() {
    local idx name status
    echo ""
    echo "   [1] Suspender um usuário"
    echo "   [2] Reativar um usuário"
    echo "   [3] Suspender TODOS"
    echo "   [4] Reativar TODOS"
    echo "   [0] Voltar"
    read -rp "Opção: " opt

    case "$opt" in
        1)
            idx="$(select_user)"
            name="$(jq -r ".[$idx - 1].name" "$XRAY_USERS")"
            jq --argjson idx "$((idx - 1))" '.[$idx].suspended = true' "$XRAY_USERS" > "$XRAY_USERS.tmp"
            mv "$XRAY_USERS.tmp" "$XRAY_USERS"
            info "Usuário '$name' suspenso."
            ;;
        2)
            idx="$(select_user)"
            name="$(jq -r ".[$idx - 1].name" "$XRAY_USERS")"
            jq --argjson idx "$((idx - 1))" '.[$idx].suspended = false' "$XRAY_USERS" > "$XRAY_USERS.tmp"
            mv "$XRAY_USERS.tmp" "$XRAY_USERS"
            info "Usuário '$name' reativado."
            ;;
        3)
            jq 'map(if .suspended then . else . + {suspended: true} end)' "$XRAY_USERS" > "$XRAY_USERS.tmp"
            mv "$XRAY_USERS.tmp" "$XRAY_USERS"
            info "Todos os usuários foram suspensos."
            ;;
        4)
            jq 'map(. + {suspended: false})' "$XRAY_USERS" > "$XRAY_USERS.tmp"
            mv "$XRAY_USERS.tmp" "$XRAY_USERS"
            info "Todos os usuários foram reativados."
            ;;
        0) return ;;
        *) return ;;
    esac

    chmod 600 "$XRAY_USERS"
    apply_config
}

# --------------------------------------------------------------------------- #
# Gerenciar portas                                                            #
# --------------------------------------------------------------------------- #
manage_ports() {
    local port network count
    echo ""
    list_portas
    echo "   [1] Adicionar porta"
    echo "   [2] Remover porta"
    echo "   [0] Voltar"
    read -rp "Opção: " opt

    case "$opt" in
        1)
            read -rp "Porta a adicionar (1-65535): " port
            validate_port "$port"
            read -rp "Rede [tcp/kcp (Enter=tcp)]: " network
            network="${network:-tcp}"
            if [[ "$network" != "tcp" && "$network" != "kcp" ]]; then
                die "Rede inválida: use tcp ou kcp."
            fi
            jq --argjson port "$port" --arg network "$network" \
                '.ports += [{"port": $port, "network": $network}]' \
                "$XRAY_SETTINGS" > "$XRAY_SETTINGS.tmp"
            mv "$XRAY_SETTINGS.tmp" "$XRAY_SETTINGS"
            chmod 600 "$XRAY_SETTINGS"
            info "Porta $port ($network) adicionada."
            apply_config || true
            ;;
        2)
            count="$(jq '.ports | length' "$XRAY_SETTINGS")"
            if [[ "$count" -le 1 ]]; then
                count="0"
            else
                count="1"
            fi
            if [[ "$count" -eq 0 ]]; then
                warn "É necessário manter pelo menos uma porta."
                return
            fi
            read -rp "Porta a remover: " port
            if ! jq -e --argjson p "$port" 'any(.ports[]; .port == $p)' "$XRAY_SETTINGS" >/dev/null 2>&1; then
                die "A porta $port não está cadastrada."
            fi
            jq --argjson port "$port" \
                '.ports |= map(select(.port != $port))' \
                "$XRAY_SETTINGS" > "$XRAY_SETTINGS.tmp"
            mv "$XRAY_SETTINGS.tmp" "$XRAY_SETTINGS"
            chmod 600 "$XRAY_SETTINGS"
            info "Porta $port removida."
            apply_config || true
            ;;
        0) return ;;
        *) return ;;
    esac
}

# --------------------------------------------------------------------------- #
# Gerenciar Xray                                                              #
# --------------------------------------------------------------------------- #
manage_xray() {
    echo ""
    echo "   [1] Status"
    echo "   [2] Reiniciar"
    echo "   [3] Parar"
    echo "   [4] Iniciar"
    echo "   [5] Ver logs (tempo real)"
    echo "   [6] Ver config gerada"
    echo "   [7] Ativar expiração automática (cron)"
    echo "   [0] Voltar"
    read -rp "Opção: " opt

    case "$opt" in
        1)
            systemctl status "$XRAY_SERVICE" --no-pager 2>&1 | head -30 || true
            ;;
        2)
            systemctl restart "$XRAY_SERVICE" && info "Xray reiniciado."
            ;;
        3)
            systemctl stop "$XRAY_SERVICE" && info "Xray parado."
            ;;
        4)
            systemctl start "$XRAY_SERVICE" && info "Xray iniciado."
            ;;
        5)
            journalctl -u "$XRAY_SERVICE" -f
            ;;
        6)
            cat "$XRAY_CONFIG"
            ;;
        7)
            install_cron
            ;;
        0) return ;;
        *) return ;;
    esac
}

install_cron() {
    local cron_file="/etc/cron.d/xray-enforce"
    cat > "$cron_file" <<EOF
0 * * * * root /usr/local/sbin/xray-menu --enforce >/dev/null 2>&1
EOF
    chmod 644 "$cron_file"
    info "Cron instalado: verifica expirados/suspensos a cada hora."
}

# --------------------------------------------------------------------------- #
# Banner                                                                        #
# --------------------------------------------------------------------------- #
banner() {
    clear
    echo ""
    printf '%s\n' "$(c_bold '==============================================')"
    printf '%s\n' "$(c_bold '   XRAY MANAGER  -  GERENCIAMENTO NA VPS')"
    printf '%s\n' "$(c_bold '==============================================')"
    echo ""
    ps -C xray >/dev/null 2>&1 && printf '   Xray: %s\n' "$(c_green 'RODANDO')" || printf '   Xray: %s\n' "$(c_red 'PARADO')"
    printf '   Usuários: %s\n' "$(user_count)"
    printf '   Config: %s\n\n' "$XRAY_CONFIG"
}

# --------------------------------------------------------------------------- #
# Menu principal                                                               #
# --------------------------------------------------------------------------- #
main_menu() {
    while true; do
        banner
        echo "   1. Criar usuário"
        echo "   2. Data"
        echo "   3. Limite"
        echo "   4. Suspender"
        echo "   5. Gerenciar portas"
        echo "   6. Gerenciar Xray"
        echo "   7. Sair"
        echo ""
        read -rp "Escolha uma opção: " opt

        case "$opt" in
            1) create_user ;;
            2) manage_date ;;
            3) manage_limit ;;
            4) manage_suspend ;;
            5) manage_ports ;;
            6) manage_xray ;;
            7)
                echo ""
                info "Saindo..."
                exit 0
                ;;
            *) warn "Opção inválida: $opt" ;;
        esac
        echo ""
        read -rp "Enter para continuar..." _
    done
}

# --------------------------------------------------------------------------- #
# Main                                                                         #
# --------------------------------------------------------------------------- #
main() {
    require_root
    ensure_tools
    ensure_files

    if [[ "${1:-}" == "--enforce" ]]; then
        enforce
        exit 0
    fi

    main_menu
}

main "$@"
