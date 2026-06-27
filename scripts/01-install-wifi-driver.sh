#!/bin/bash
# =============================================================================
# 01-install-wifi-driver.sh
# Instalação do driver Wi-Fi SSV6X5X para TV Box RK322x (ARMv7l)
# Kernel alvo: 6.x (current-rockchip)
# Repositório do driver: https://github.com/cdhigh/armbian_sv6256p
# =============================================================================

set -e  # Abortar em caso de erro

# --- Cores para output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log()  { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
err()  { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

# --- Verificações iniciais ---
echo ""
echo "============================================="
echo " Driver Wi-Fi SSV6X5X — RK322x (ARMv7l)"
echo "============================================="
echo ""

[ "$(id -u)" -eq 0 ] || err "Execute como root: sudo bash $0"

ARCH=$(uname -m)
[ "$ARCH" = "armv7l" ] || warn "Arquitetura detectada: $ARCH (esperado: armv7l). Prosseguindo..."

KERNEL=$(uname -r)
info "Kernel: $KERNEL"
info "Arquitetura: $ARCH"

# Verificar se os headers estão instalados
if [ ! -d "/lib/modules/$KERNEL/build" ]; then
    warn "Headers do kernel não encontrados. Instalando..."
    apt-get install -y linux-headers-current-rockchip || \
        err "Não foi possível instalar os headers. Verifique sua conexão com a internet."
fi
log "Headers do kernel encontrados: /lib/modules/$KERNEL/build"

# --- Instalar dependências ---
info "Instalando dependências..."
apt-get update -qq
apt-get install -y dkms build-essential git
log "Dependências instaladas."

# --- Blacklist do módulo conflitante ANTES de instalar o driver correto ---
info "Aplicando blacklist do módulo conflitante ssv6051..."
cat > /etc/modprobe.d/blacklist-ssv6051.conf << 'EOF'
# O módulo ssv6051 conflita com o ssv6x5x no barramento SDIO,
# causando falha de calibração de RF. Deve ser bloqueado permanentemente.
blacklist ssv6051
blacklist ssv6200
EOF
log "Blacklist aplicado: /etc/modprobe.d/blacklist-ssv6051.conf"

# Remover módulo conflitante se estiver carregado
rmmod ssv6051 2>/dev/null && warn "ssv6051 removido da memória." || true
rmmod ssv6200 2>/dev/null && warn "ssv6200 removido da memória." || true
rmmod ssv6x5x 2>/dev/null && true || true

# --- Clonar e instalar o driver via DKMS ---
info "Clonando repositório do driver..."
TMPDIR=$(mktemp -d)
git clone https://github.com/cdhigh/armbian_sv6256p.git "$TMPDIR/armbian_sv6256p"
log "Repositório clonado em $TMPDIR/armbian_sv6256p"

info "Instalando via DKMS (isso pode levar alguns minutos)..."
cd "$TMPDIR/armbian_sv6256p"
bash ./install-dkms.sh
log "Driver instalado via DKMS."

# --- Instalar firmware ---
info "Instalando arquivos de firmware..."
cp "$TMPDIR/armbian_sv6256p/ssv6x5x-wifi.cfg" /lib/firmware/
cp "$TMPDIR/armbian_sv6256p/ssv6x5x-sw.bin"  /lib/firmware/
log "Firmware copiado para /lib/firmware/"

# --- Configurar paths do firmware no modprobe ---
cat > /etc/modprobe.d/ssv6x5x.conf << 'EOF'
options ssv6x5x stacfgpath="/lib/firmware/ssv6x5x-wifi.cfg" cfgfirmwarepath="/lib/firmware/ssv6x5x-sw.bin"
EOF
log "Configuração do modprobe: /etc/modprobe.d/ssv6x5x.conf"

# --- Atualizar initramfs para persistir o blacklist no boot ---
info "Atualizando initramfs..."
update-initramfs -u
log "initramfs atualizado."

# --- Limpar diretório temporário ---
rm -rf "$TMPDIR"

# --- Carregar o módulo e verificar ---
info "Carregando o módulo ssv6x5x..."
modprobe ssv6x5x || err "Falha ao carregar o módulo. Verifique: dmesg | grep -i ssv"

echo ""
echo "--- Verificação ---"
if lsmod | grep -q ssv6x5x; then
    log "Módulo ssv6x5x carregado com sucesso."
else
    err "Módulo ssv6x5x não encontrado após modprobe."
fi

dkms status | grep ssv && log "DKMS: instalado e registrado." || warn "Verifique: dkms status"

echo ""
echo "============================================="
echo " Instalação concluída!"
echo "============================================="
echo ""
echo " Próximo passo: reinicie o sistema e verifique:"
echo "   ip link show wlan0"
echo "   # Esperado: state UP"
echo ""
echo " Depois, configure o Access Point:"
echo "   sudo bash scripts/02-setup-ap.sh"
echo ""
