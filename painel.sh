#!/bin/bash
# ============================================================================
#  PAINEL SSH + XRAY - Gerenciamento completo de VPS
#  Versão: 1.0
#  Linguagem: PT-BR
# ============================================================================

# Verificar se está rodando como root
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[31m[ERRO] Este painel precisa ser executado como root!\e[0m"
    echo "Use: sudo bash $0"
    exit 1
fi

# Diretório base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="$SCRIPT_DIR/modules"

# Carregar módulos
source "$MODULES_DIR/colors.sh"
source "$MODULES_DIR/common.sh"
source "$MODULES_DIR/menu.sh"
source "$MODULES_DIR/ssh_manager.sh"
source "$MODULES_DIR/xray_manager.sh"
source "$MODULES_DIR/system_info.sh"
source "$MODULES_DIR/monitor.sh"
source "$MODULES_DIR/utils.sh"

# ============================================================================
# INICIALIZAÇÃO
# ============================================================================
clear
banner_init
checar_dependencias
checar_xray_instalado
menu_principal
