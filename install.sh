#!/bin/bash
# ============================================================================
# INSTALADOR DO PAINEL SSH + XRAY
# Instala o painel em /opt/painel-ssh-xray e cria um comando 'painel'
# ============================================================================

set -e

if [ "$EUID" -ne 0 ]; then
    echo "[ERRO] Execute como root (sudo)."
    exit 1
fi

DIR_ATUAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR_DEST="/opt/painel-ssh-xray"

echo "=========================================="
echo "  Instalador Painel SSH + Xray"
echo "=========================================="
echo ""

# Verificar bash e dependências essenciais
echo "[*] Verificando dependências..."
apt update -qq >/dev/null 2>&1 || true
apt install -y -qq bash curl wget openssh-server openssl jq qrencode net-tools iproute2 procps >/dev/null 2>&1 || \
    yum install -y -q bash curl wget openssh-server openssl jq qrencode net-tools iproute procps-ng >/dev/null 2>&1 || true
echo "[✓] Dependências OK."

# Copiar arquivos
echo "[*] Instalando em $DIR_DEST..."
mkdir -p "$DIR_DEST"
cp -r "$DIR_ATUAL"/modules "$DIR_DEST/"
cp "$DIR_ATUAL/painel.sh" "$DIR_DEST/"
chmod +x "$DIR_DEST/painel.sh"

# Criar link simbólico
ln -sf "$DIR_DEST/painel.sh" /usr/local/bin/painel
echo "[✓] Comando 'painel' criado em /usr/local/bin/painel"

echo ""
echo "=========================================="
echo "  Instalação concluída!"
echo "=========================================="
echo ""
echo "Para abrir o painel, execute:"
echo "  painel"
echo ""
echo "Ou diretamente:"
echo "  bash $DIR_DEST/painel.sh"
echo ""
echo "O script deve ser executado como root."
