#!/bin/bash
# =============================================================================
# 01-install-wifi-driver.sh
# Instalação do driver Wi-Fi para TV Box RK322x (ARMv7l)
#
# Identifica qual das três variantes de chip está presente e instala o driver
# correto:
#   - Realtek RTL8723BS  -> r8723bs (nativo no kernel; só precisa de firmware)
#   - RSV6200A           -> ssv6051 (nativo no kernel, sem compilação)
#   - SSV6501P / SV6256P -> ssv6x5x (compilação via DKMS)
#
# Como a identificação funciona (detalhes em docs/01-identificacao-hardware.md):
#   - O RTL8723BS tem driver nativo que se liga sozinho ao dispositivo assim
#     que o SDIO é enumerado. A evidência está no dmesg e basta procurá-la.
#   - O RSV6200A e o SSV6X5X não se anunciam. O ssv6051 falha com a mesma
#     saída nos dois, então não serve para distingui-los. Só o ssv6x5x lê o
#     Chip ID de verdade e rejeita o chip com erro -22 quando ele não é da
#     família SSV6X5X. Por isso o script compila o ssv6x5x via DKMS e o usa
#     como sonda, mesmo em unidades que acabam usando o ssv6051. Custa alguns
#     minutos a mais.
#   - Não procure o texto "RSV6200" no dmesg. A string de chip que aparece nos
#     logs é SSV6200Ax-..., nunca RSV6200x. "RSV6200A" é só o nome adotado para
#     essa família.
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
# O apt upgrade pode ter instalado um kernel novo. Se o kernel em execução não
# bater com os headers recém-instalados, o DKMS vai falhar. O apt cria
# /var/run/reboot-required quando o kernel é atualizado.
if [ -f /var/run/reboot-required ]; then
    echo ""
    warn "Reboot necessário antes de continuar."
    echo ""
    echo " O apt upgrade instalou um novo kernel. O sistema precisa reiniciar"
    echo " para carregá-lo antes de compilar o driver."
    echo ""
    echo " Depois do reboot, execute novamente:"
    echo "   sudo bash scripts/01-install-wifi-driver.sh"
    echo ""
    exit 0
fi

# Reler o kernel depois da atualização
KERNEL=$(uname -r)

# --- Instalar dependências base ---
info "Instalando dependências..."
apt-get install -y dkms build-essential git linux-headers-current-rockchip
log "Dependências instaladas."

if [ ! -d "/lib/modules/$KERNEL/build" ]; then
    echo ""
    echo " Headers não encontrados em /lib/modules/$KERNEL/build."
    echo " Isso costuma indicar que o kernel foi atualizado mas o sistema ainda"
    echo " não foi reiniciado. Reinicie e execute o script novamente."
    echo ""
    err "Headers ausentes para o kernel $KERNEL."
fi
log "Headers confirmados: /lib/modules/$KERNEL/build"

# =============================================================================
# Driver ssv6x5x: instalação via DKMS + firmware
# Necessário em todo caso que não seja Realtek, porque é ele que faz a sondagem.
# =============================================================================
install_ssv6x5x() {
    if dkms status | grep -qi "ssv6x5x.*installed"; then
        log "ssv6x5x já instalado via DKMS."
    else
        info "Clonando repositório do driver..."
        local tmp
        tmp=$(mktemp -d)
        git clone https://github.com/cdhigh/armbian_sv6256p.git "$tmp/armbian_sv6256p"

        info "Instalando via DKMS (isso pode levar alguns minutos)..."
        ( cd "$tmp/armbian_sv6256p" && bash ./install-dkms.sh )

        info "Instalando arquivos de firmware..."
        cp "$tmp/armbian_sv6256p/ssv6x5x-wifi.cfg" /lib/firmware/
        cp "$tmp/armbian_sv6256p/ssv6x5x-sw.bin"   /lib/firmware/
        rm -rf "$tmp"
    fi

    cat > /etc/modprobe.d/ssv6x5x.conf << 'EOT'
options ssv6x5x stacfgpath="/lib/firmware/ssv6x5x-wifi.cfg" cfgfirmwarepath="/lib/firmware/ssv6x5x-sw.bin"
EOT

    dkms status | grep -qi "ssv6x5x.*installed" \
        || err "Falha ao instalar o ssv6x5x via DKMS. Verifique: dkms status"
    log "ssv6x5x instalado via DKMS."
}

# =============================================================================
# DETECÇÃO DO CHIP WI-FI
# =============================================================================
info "Detectando chip Wi-Fi via barramento SDIO..."

CHIPID_LINE=""

if dmesg | grep -qi "rtl8723bs"; then
    # O driver nativo r8723bs já se ligou sozinho ao dispositivo. É sinal
    # inequívoco de Realtek RTL8723BS, e nem precisa sondar com o ssv6x5x.
    CHIP_TYPE="RTL8723BS"
    DRIVER_MODULE="r8723bs"
else
    rmmod ssv6x5x 2>/dev/null || true
    rmmod ssv6051 2>/dev/null || true
    sleep 1

    install_ssv6x5x

    info "Sondando o chip com o ssv6x5x..."
    DMESG_MARK=$(dmesg | wc -l)
    modprobe ssv6x5x 2>/dev/null || true

    # Espera até 10 s por um dos dois sinais: o Chip ID ou a rejeição -22.
    PROBE_LOG=""
    for _ in $(seq 1 10); do
        sleep 1
        PROBE_LOG=$(dmesg | tail -n +"$((DMESG_MARK + 1))")
        echo "$PROBE_LOG" | grep -qiE "CHIP ID:|probe with driver ssv6x5x failed with error -22" && break
    done

    CHIPID_LINE=$(echo "$PROBE_LOG" | grep -i "CHIP ID:" | tail -1 || true)
    REJECT_LINE=$(echo "$PROBE_LOG" | grep -i "probe with driver ssv6x5x failed with error -22" || true)

    rmmod ssv6x5x 2>/dev/null || true
    sleep 1

    if [ -n "$REJECT_LINE" ]; then
        # O ssv6x5x rejeitou o chip: não é da família SSV6X5X.
        CHIP_TYPE="RSV6200A"
        DRIVER_MODULE="ssv6051"
    elif [ -n "$CHIPID_LINE" ]; then
        CHIP_TYPE="SSV6X5X"
        DRIVER_MODULE="ssv6x5x"
    else
        err "Chip Wi-Fi não identificado (nem CHIP ID, nem erro -22, nem Realtek). Verifique: dmesg | grep -iE 'ssv|sdio|wlan'"
    fi
fi

echo ""
echo "============================================="
echo " Chip detectado: $CHIP_TYPE (driver: $DRIVER_MODULE)"
[ -n "$CHIPID_LINE" ] && echo " ${CHIPID_LINE}"
echo "============================================="
echo ""

# =============================================================================
# FLUXO REALTEK RTL8723BS — driver nativo r8723bs
# =============================================================================
if [ "$CHIP_TYPE" = "RTL8723BS" ]; then

    info "Removendo blacklists dos drivers SSV (não se aplicam a este chip)..."
    rm -f /etc/modprobe.d/blacklist-ssv6x5x.conf /etc/modprobe.d/blacklist-ssv6051.conf
    rm -f /etc/modules-load.d/ssv6051.conf

    # Sem o firmware, o r8723bs carrega e a wlan0 aparece, mas o rádio nunca
    # recebe firmware ("Direct firmware load ... failed with error -2") e o AP
    # fica de pé sem transmitir nada.
    info "Instalando firmware-realtek..."
    apt-get install -y firmware-realtek || warn "Falha ao instalar firmware-realtek. Confira se non-free-firmware está em /etc/apt/sources.list."

    info "Atualizando initramfs..."
    update-initramfs -u

    modprobe r8723bs 2>/dev/null || true

# =============================================================================
# FLUXO RSV6200A — driver nativo ssv6051
# =============================================================================
elif [ "$CHIP_TYPE" = "RSV6200A" ]; then

    info "Aplicando blacklist do ssv6x5x (conflita com ssv6051 no SDIO)..."
    cat > /etc/modprobe.d/blacklist-ssv6x5x.conf << 'EOT'
# ssv6x5x conflita com ssv6051 no barramento SDIO para o chip RSV6200A.
# O ssv6x5x continua compilado via DKMS porque é a sonda de identificação,
# mas não deve carregar nesta TV box.
blacklist ssv6x5x
EOT
    log "Blacklist aplicado: /etc/modprobe.d/blacklist-ssv6x5x.conf"

    rm -f /etc/modprobe.d/blacklist-ssv6051.conf

    info "Configurando carregamento automático do ssv6051 no boot..."
    echo "ssv6051" > /etc/modules-load.d/ssv6051.conf
    log "ssv6051 adicionado em /etc/modules-load.d/ssv6051.conf"

    [ -f /lib/firmware/ssv6051-sw.bin ] \
        || warn "/lib/firmware/ssv6051-sw.bin ausente. Imagens montadas do zero não trazem o firmware do ssv6051; veja docs/03b-driver-wifi-rsv6200a.md."

    info "Atualizando initramfs..."
    update-initramfs -u

    info "Carregando o módulo ssv6051..."
    modprobe ssv6051 || err "Falha ao carregar ssv6051. Verifique: dmesg | grep -i ssv"

    CALIB=$(dmesg | grep -i "calibration" | tail -1 || true)
    echo " Calibração: $CALIB"

# =============================================================================
# FLUXO SSV6X5X — driver externo via DKMS
# =============================================================================
else

    info "Aplicando blacklist do ssv6051 (conflita com ssv6x5x no SDIO)..."
    cat > /etc/modprobe.d/blacklist-ssv6051.conf << 'EOT'
# ssv6051 conflita com ssv6x5x no barramento SDIO para o chip SSV6501P/SV6256P,
# causando falha de calibração de RF. Deve ser bloqueado permanentemente.
blacklist ssv6051
blacklist ssv6200
EOT
    log "Blacklist aplicado: /etc/modprobe.d/blacklist-ssv6051.conf"

    rm -f /etc/modprobe.d/blacklist-ssv6x5x.conf
    rm -f /etc/modules-load.d/ssv6051.conf

    info "Atualizando initramfs..."
    update-initramfs -u

    info "Carregando o módulo ssv6x5x..."
    modprobe ssv6x5x || err "Falha ao carregar ssv6x5x. Verifique: dmesg | grep -i ssv"
fi

# --- Verificação ---
echo ""
echo "--- Verificação ---"
if lsmod | grep -q "^${DRIVER_MODULE//-/_}" || [ "$DRIVER_MODULE" = "r8723bs" ]; then
    log "Driver $DRIVER_MODULE ativo."
else
    err "$DRIVER_MODULE não encontrado depois do modprobe."
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