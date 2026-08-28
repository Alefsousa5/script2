#!/bin/bash
# ============================================================================
#  DESINSTALADOR DO PAINEL SSH + XRAY
#  (mantém Xray e configurações do SSH intactos por padrão)
# ============================================================================
set -e
if [ "$EUID" -ne 0 ]; then
    echo "Execute como root: sudo bash uninstall.sh"; exit 1
fi
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BOLD='\033[1m'; NC='\033[0m'

echo -e "${BOLD}⚠️  DESINSTALAÇÃO DO PAINEL SSH + XRAY${NC}"
echo ""
echo "O que será removido?"
echo "  - /opt/painel-ssh-xray/ (scripts do painel)"
echo "  - /usr/local/bin/painel"
echo "  - /usr/local/bin/painel-update"
echo "  - /usr/local/bin/painel-uninstall"
echo ""
echo "O que NÃO será removido (por padrão):"
echo "  - Xray e suas configurações (/usr/local/bin/xray, /usr/local/etc/xray)"
echo "  - Configurações do SSH (/etc/ssh/sshd_config)"
echo "  - Usuários criados"
echo "  - Contas Xray criadas"
echo ""
read -p "Continuar com a desinstalação? [s/N]: " c
if [ "$c" != "s" ] && [ "$c" != "S" ]; then
    echo "Cancelado."; exit 0
fi

rm -f /usr/local/bin/painel /usr/local/bin/painel-update /usr/local/bin/painel-uninstall
rm -rf /opt/painel-ssh-xray

echo ""
echo -e "${GREEN}✓ Painel removido.${NC}"
echo ""
read -p "Deseja remover TAMBÉM o Xray e todos os seus dados? [s/N]: " xc
if [ "$xc" = "s" ] || [ "$xc" = "S" ]; then
    echo "Removendo Xray..."
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove 2>&1 | tail -5
    rm -rf /usr/local/etc/xray /var/log/xray /usr/local/bin/xray 2>/dev/null || true
    echo -e "${GREEN}✓ Xray removido.${NC}"
fi
echo "Desinstalação concluída."
