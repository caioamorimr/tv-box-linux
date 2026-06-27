#!/bin/bash
# =============================================================================
# 02-setup-ap.sh
# Configuração de Access Point Wi-Fi na TV Box RK322x
# Dependências: hostapd, dnsmasq, iptables
# Topologia: Internet via Ethernet (end0) → NAT → Wi-Fi AP (wlan0)
# =============================================================================

set -e

# =============================================================================
# CONFIGURAÇÕES — edite aqui antes de executar
# =============================================================================

SSID="MeuHotspot"          # Nome da rede Wi-Fi
PASSPHRASE="SuaSenhaAqui"  # Senha da rede (mínimo 8 caracteres)
CHANNEL="6"                 # Canal Wi-Fi (1, 6 ou 11 para 2.4 GHz)

AP_IFACE="wlan0"           # Interface Wi-Fi (Access Point)
WAN_IFACE="end0"           # Interface com internet (Ethernet)

AP_IP="192.168.50.1"       # IP da TV box na rede do hotspot
DHCP_START="192.168.50.10" # Início da faixa DHCP para clientes
DHCP_END="192.168.50.100"  # Fim da faixa DHCP para clientes
DHCP_MASK="255.255.255.0"  # Máscara de sub-rede
DHCP_LEASE="24h"           # Tempo de validade do IP dos clientes

# =============================================================================
# NÃO EDITE ABAIXO DESTA LINHA
# =============================================================================

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
echo " Setup de Access Point — TV Box RK322x"
echo "============================================="
echo ""
echo " SSID      : $SSID"
echo " Canal     : $CHANNEL"
echo " IP do AP  : $AP_IP"
echo " Faixa DHCP: $DHCP_START — $DHCP_END"
echo " Internet  : $WAN_IFACE → NAT → $AP_IFACE"
echo ""

# --- Verificações iniciais ---
[ "$(id -u)" -eq 0 ] || err "Execute como root: sudo bash $0"

ip link show "$AP_IFACE" &>/dev/null  || err "Interface $AP_IFACE não encontrada. O driver Wi-Fi está instalado?"
ip link show "$WAN_IFACE" &>/dev/null || err "Interface $WAN_IFACE não encontrada. O cabo Ethernet está conectado?"

[ ${#PASSPHRASE} -ge 8 ] || err "A senha deve ter no mínimo 8 caracteres."

# --- Instalar dependências ---
info "Instalando dependências..."
apt-get update -qq
apt-get install -y hostapd dnsmasq iptables iptables-persistent
log "Dependências instaladas."

# --- Parar serviços conflitantes ---
info "Parando serviços conflitantes..."
systemctl stop NetworkManager 2>/dev/null && warn "NetworkManager parado." || true
systemctl stop wpa_supplicant 2>/dev/null && warn "wpa_supplicant parado." || true
pkill -9 wpa_supplicant 2>/dev/null || true
pkill -9 hostapd 2>/dev/null || true

ip link set "$AP_IFACE" down
sleep 1
ip link set "$AP_IFACE" up
log "Interface $AP_IFACE reiniciada."

# --- Configurar IP fixo no wlan0 ---
info "Atribuindo IP fixo $AP_IP ao $AP_IFACE..."
ip addr flush dev "$AP_IFACE"
ip addr add "${AP_IP}/24" dev "$AP_IFACE"
ip link set "$AP_IFACE" up
log "IP $AP_IP atribuído a $AP_IFACE."

# --- Configurar hostapd ---
info "Configurando hostapd..."
systemctl unmask hostapd

cat > /etc/hostapd/hostapd.conf << EOF
interface=${AP_IFACE}
driver=nl80211
ssid=${SSID}
hw_mode=g
channel=${CHANNEL}
wmm_enabled=0
auth_algs=1
wpa=2
wpa_passphrase=${PASSPHRASE}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

# Apontar o daemon para o arquivo de configuração
sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
# Garantir que a linha existe mesmo se não estava comentada
grep -q 'DAEMON_CONF=' /etc/default/hostapd || \
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' >> /etc/default/hostapd

log "hostapd configurado: /etc/hostapd/hostapd.conf"

# --- Configurar dnsmasq ---
info "Configurando dnsmasq (DHCP)..."
[ -f /etc/dnsmasq.conf ] && cp /etc/dnsmasq.conf /etc/dnsmasq.conf.bak && \
    warn "Backup do dnsmasq.conf salvo em /etc/dnsmasq.conf.bak"

cat > /etc/dnsmasq.conf << EOF
interface=${AP_IFACE}
bind-interfaces
dhcp-range=${DHCP_START},${DHCP_END},${DHCP_MASK},${DHCP_LEASE}
dhcp-option=3,${AP_IP}
dhcp-option=6,8.8.8.8,8.8.4.4
EOF

log "dnsmasq configurado: /etc/dnsmasq.conf"

# --- Configurar IP forwarding ---
info "Ativando IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward

# Tornar permanente
sed -i '/ip_forward/d' /etc/sysctl.conf
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p -q
log "IP forwarding ativado e persistido em /etc/sysctl.conf"

# --- Configurar NAT via iptables ---
info "Configurando NAT (iptables)..."

# Limpar regras anteriores relacionadas ao AP para evitar duplicatas
iptables -t nat -D POSTROUTING -o "$WAN_IFACE" -j MASQUERADE 2>/dev/null || true
iptables -D FORWARD -i "$AP_IFACE" -o "$WAN_IFACE" -j ACCEPT 2>/dev/null || true
iptables -D FORWARD -i "$WAN_IFACE" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

# Adicionar regras novas
iptables -t nat -A POSTROUTING -o "$WAN_IFACE" -j MASQUERADE
iptables -A FORWARD -i "$AP_IFACE" -o "$WAN_IFACE" -j ACCEPT
iptables -A FORWARD -i "$WAN_IFACE" -o "$AP_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT

# Persistir regras do iptables
netfilter-persistent save
log "Regras de NAT configuradas e salvas (iptables-persistent)."

# --- IP fixo persistente no boot via rc.local ---
info "Configurando IP fixo persistente no boot..."
cat > /etc/rc.local << EOF
#!/bin/bash
# IP fixo do Access Point no wlan0
ip addr flush dev ${AP_IFACE}
ip addr add ${AP_IP}/24 dev ${AP_IFACE}
ip link set ${AP_IFACE} up
exit 0
EOF
chmod +x /etc/rc.local
log "rc.local configurado."

# --- Habilitar e iniciar serviços ---
info "Habilitando serviços no boot..."
systemctl enable hostapd
systemctl enable dnsmasq
log "hostapd e dnsmasq habilitados no boot."

info "Iniciando serviços..."
systemctl start dnsmasq
sleep 1
systemctl start hostapd
sleep 2

# --- Verificação final ---
echo ""
echo "--- Verificação Final ---"
echo ""

AP_STATUS=$(systemctl is-active hostapd)
DNSMASQ_STATUS=$(systemctl is-active dnsmasq)
FORWARD=$(cat /proc/sys/net/ipv4/ip_forward)
IP_CHECK=$(ip addr show "$AP_IFACE" | grep -c "$AP_IP" || true)

[ "$AP_STATUS" = "active" ]      && log "hostapd: active (running)" \
                                   || warn "hostapd: $AP_STATUS — verifique: journalctl -u hostapd"
[ "$DNSMASQ_STATUS" = "active" ] && log "dnsmasq: active (running)" \
                                   || warn "dnsmasq: $DNSMASQ_STATUS — verifique: journalctl -u dnsmasq"
[ "$FORWARD" = "1" ]             && log "IP forwarding: ativado" \
                                   || warn "IP forwarding: DESATIVADO"
[ "$IP_CHECK" -ge 1 ]            && log "IP $AP_IP atribuído a $AP_IFACE" \
                                   || warn "IP $AP_IP não encontrado em $AP_IFACE"

echo ""
echo "============================================="
echo " Access Point configurado!"
echo "============================================="
echo ""
echo " Rede Wi-Fi : $SSID"
echo " Senha      : $PASSPHRASE"
echo " Gateway    : $AP_IP"
echo " Internet   : via $WAN_IFACE (Ethernet)"
echo ""
echo " Para verificar clientes conectados:"
echo "   cat /var/lib/misc/dnsmasq.leases"
echo "   sudo hostapd_cli all_sta"
echo ""
echo " Para ver logs em tempo real:"
echo "   journalctl -u hostapd -f"
echo ""
