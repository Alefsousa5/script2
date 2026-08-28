#!/bin/bash
# ============================================================================
#  install.sh - alias para o instalador completo setup.sh
#
#  Use preferencialmente o setup.sh, que suporta instalação em 1 clique:
#    bash <(curl -sL https://raw.githubusercontent.com/Alefsousa5/script2/arena/01a048cf-script2/setup.sh)
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/setup.sh" "$@"
