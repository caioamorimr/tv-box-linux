#!/bin/bash
# =============================================================================
# 01-install-wifi-driver.sh
# Instalação do driver Wi-Fi para TV Box RK322x (ARMv7l)
# Detecta automaticamente o chip presente e instala o driver correto:
#   - SSV6501P / SV6256P → driver ssv6x5x (compilação via DKMS)
#   - RSV6200A           → driver ssv6051  (nativo no kernel, sem compilação)
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
err()  { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

echo ""
echo "============================================="
echo " Driver Wi-Fi — TV Box RK322x (ARMv7l)"
echo "============================================="
echo ""

# --- Verificações iniciais ---
[ "$(id -u)" -eq 0 ] || err "Execute como root: sudo bash $0"

ARCH=$(uname -m)
KERNEL=$(uname -r)
info "Kernel     : $KERNEL"
info "Arquitetura: $ARCH"
[ "$ARCH" = "armv7l" ] || warn "Arquitetura inesperada: $ARCH (esperado: armv7l)"

# --- Atualizar sistema (alinha kernel e headers) ---
info "Atualizando sistema para garantir alinhamento entre kernel e headers..."
apt-get update -qq
apt-get upgrade -y -qq
log "Sistema atualizado."

# --- Verificar se reboot é necessário antes de prosseguir ---
# O apt upgrade pode ter instalado um kernel novo. Se o kernel atual não bater
# com os headers recém-instalados, o DKMS vai falhar. Detectamos isso cedo
# via /var/run/reboot-required, criado automaticamente pelo apt quando o kernel
# é atualizado.
if [ -f /var/run/reboot-required ]; then
    echo ""
    echo "============================================="
    warn "Reboot necessário antes de continuar."
    echo "============================================="
    echo ""
    echo " O apt upgrade instalou um novo kernel."
    echo " O sistema precisa reiniciar para carregá-lo"
    echo " antes de compilar o driver."
    echo ""
    echo " Após o reboot, execute novamente:"
    echo "   sudo bash scripts/01-install-wifi-driver.sh"
    echo ""
    exit 0
fi

# Reler kernel após possível atualização sem reboot
KERNEL=$(uname -r)

# --- Instalar dependências base ---
info "Instalando dependências..."
apt-get install -y dkms build-essential git linux-headers-current-rockchip
log "Dependências instaladas."

# Verificar se os headers estão no lugar certo
if [ ! -d "/lib/modules/$KERNEL/build" ]; then
    echo ""
    echo "============================================="
    err "Headers não encontrados em /lib/modules/$KERNEL/build."
    echo "============================================="
    echo ""
    echo " Isso pode indicar que o kernel foi atualizado"
    echo " mas o sistema ainda não foi reiniciado."
    echo ""
    echo " Reinicie e execute o script novamente:"
    echo "   sudo reboot"
    echo ""
    exit 1
fi
log "Headers confirmados: /lib/modules/$KERNEL/build"

# =============================================================================
# DETECÇÃO DO CHIP WI-FI
# Carrega ssv6051 (nativo) temporariamente para ler o Chip ID via SDIO
# =============================================================================
info "Detectando chip Wi-Fi via barramento SDIO..."

rmmod ssv6x5x 2>/dev/null || true
rmmod ssv6051 2>/dev/null || true
sleep 1

modprobe ssv6051 2>/dev/null || true
sleep 4

CHIP_LINE=$(dmesg | grep -i "chip id" | tail -1)
info "Chip ID detectado: $CHIP_LINE"

rmmod ssv6051 2>/dev/null || true
sleep 1

if echo "$CHIP_LINE" | grep -qi "RSV6200"; then
    CHIP_TYPE="RSV6200A"
    log "Chip: RSV6200A — driver nativo ssv6051 (sem compilação necessária)"
else
    CHIP_TYPE="SSV6X5X"
    log "Chip: SSV6X5X (SSV6501P/SV6256P) — compilando driver externo ssv6x5x"
fi

echo ""
echo "============================================="
echo " Chip detectado: $CHIP_TYPE"
echo "============================================="
echo ""

# =============================================================================
# FLUXO RSV6200A — Driver nativo ssv6051
# =============================================================================
if [ "$CHIP_TYPE" = "RSV6200A" ]; then

    info "Aplicando blacklist do ssv6x5x (conflita com ssv6051 no SDIO)..."
    cat > /etc/modprobe.d/blacklist-ssv6x5x.conf << 'EOF'
# ssv6x5x conflita com ssv6051 no barramento SDIO para o chip RSV6200A.
# Deve ser bloqueado permanentemente nesta TV box.
blacklist ssv6x5x
EOF
    log "Blacklist aplicado: /etc/modprobe.d/blacklist-ssv6x5x.conf"

    # Remover blacklist do ssv6051 se existir de execução anterior
    rm -f /etc/modprobe.d/blacklist-ssv6051.conf
    warn "blacklist-ssv6051.conf removido (ssv6051 é o driver correto para este chip)."

    info "Configurando carregamento automático do ssv6051 no boot..."
    echo "ssv6051" > /etc/modules-load.d/ssv6051.conf
    log "ssv6051 adicionado em /etc/modules-load.d/ssv6051.conf"

    info "Atualizando initramfs..."
    update-initramfs -u
    log "initramfs atualizado."

    info "Carregando o módulo ssv6051..."
    modprobe ssv6051 || err "Falha ao carregar ssv6051. Verifique: dmesg | grep -i ssv"

    echo ""
    echo "--- Verificação ---"
    if lsmod | grep -q ssv6051; then
        log "Módulo ssv6051 carregado com sucesso."
    else
        err "ssv6051 não encontrado após modprobe."
    fi

    CALIB=$(dmesg | grep -i "calibration" | tail -1)
    echo " Calibração: $CALIB"

# =============================================================================
# FLUXO SSV6X5X — Driver externo via DKMS
# =============================================================================
else

    info "Aplicando blacklist do ssv6051 (conflita com ssv6x5x no SDIO)..."
    cat > /etc/modprobe.d/blacklist-ssv6051.conf << 'EOF'
# ssv6051 conflita com ssv6x5x no barramento SDIO para o chip SSV6501P/SV6256P,
# causando falha de calibração de RF. Deve ser bloqueado permanentemente.
blacklist ssv6051
blacklist ssv6200
EOF
    log "Blacklist aplicado: /etc/modprobe.d/blacklist-ssv6051.conf"

    # Remover blacklist do ssv6x5x se existir de execução anterior
    rm -f /etc/modprobe.d/blacklist-ssv6x5x.conf

    info "Clonando repositório do driver..."
    TMPDIR=$(mktemp -d)
    git clone https://github.com/cdhigh/armbian_sv6256p.git "$TMPDIR/armbian_sv6256p"
    log "Repositório clonado."

    info "Instalando via DKMS (isso pode levar alguns minutos)..."
    cd "$TMPDIR/armbian_sv6256p"
    bash ./install-dkms.sh
    log "Driver instalado via DKMS."

    info "Instalando arquivos de firmware..."
    cp "$TMPDIR/armbian_sv6256p/ssv6x5x-wifi.cfg" /lib/firmware/
    cp "$TMPDIR/armbian_sv6256p/ssv6x5x-sw.bin"  /lib/firmware/
    log "Firmware copiado para /lib/firmware/"

    cat > /etc/modprobe.d/ssv6x5x.conf << 'EOF'
options ssv6x5x stacfgpath="/lib/firmware/ssv6x5x-wifi.cfg" cfgfirmwarepath="/lib/firmware/ssv6x5x-sw.bin"
EOF
    log "Parâmetros do firmware: /etc/modprobe.d/ssv6x5x.conf"

    info "Atualizando initramfs..."
    update-initramfs -u
    log "initramfs atualizado."

    rm -rf "$TMPDIR"

    info "Carregando o módulo ssv6x5x..."
    modprobe ssv6x5x || err "Falha ao carregar ssv6x5x. Verifique: dmesg | grep -i ssv"

    echo ""
    echo "--- Verificação ---"
    if lsmod | grep -q ssv6x5x; then
        log "Módulo ssv6x5x carregado com sucesso."
    else
        err "ssv6x5x não encontrado após modprobe."
    fi

    dkms status | grep ssv && log "DKMS: instalado e registrado." || warn "Verifique: dkms status"

fi

# =============================================================================
# FINALIZAÇÃO
# =============================================================================
echo ""
echo "============================================="
echo " Instalação concluída! Chip: $CHIP_TYPE"
echo "============================================="
echo ""
echo " Próximo passo: reinicie e verifique:"
echo "   ip link show wlan0"
echo "   # Esperado: state UP"
echo ""
echo " Depois configure o Access Point:"
echo "   sudo bash scripts/02-setup-ap.sh"
echo ""