# ============================================================================
# CORES e ESTILOS - Módulo de cores do painel
# ============================================================================

export ESC="\033["
export RESET="${ESC}0m"
export BOLD="${ESC}1m"
export DIM="${ESC}2m"

# Cores de texto
export RED="${ESC}31m"
export GREEN="${ESC}32m"
export YELLOW="${ESC}33m"
export BLUE="${ESC}34m"
export MAGENTA="${ESC}35m"
export CYAN="${ESC}36m"
export WHITE="${ESC}37m"
export GRAY="${ESC}90m"

# Cores de fundo
export BG_RED="${ESC}41m"
export BG_GREEN="${ESC}42m"
export BG_BLUE="${ESC}44m"
export BG_MAGENTA="${ESC}45m"
export BG_CYAN="${ESC}46m"

# Função helper: imprimir mensagens
info()    { echo -e "${GREEN}[INFO]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET} $*"; }
sucesso() { echo -e "${GREEN}[✓]${RESET} $*"; }
