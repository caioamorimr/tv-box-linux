# 04 — Configuração do Access Point (Wi-Fi Hotspot)

## Visão Geral

Com o driver Wi-Fi funcionando, o objetivo seguinte foi transformar a TV Box em um **Access Point (AP)** — permitindo que outros dispositivos se conectem a ela via Wi-Fi e acessem a internet através da conexão Ethernet (`end0`).

A topologia final é:

```
Internet
   │
   │ (cabo Ethernet)
   ▼
[ end0 ] ── TV Box RK322x ── [ wlan0 ]
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
               Notebook        Celular      Tablet
             (192.168.50.73) (192.168.50.x) ...
```

---

## Por Que Não Usar o NetworkManager para o AP

A primeira tentativa foi usar o comando nativo do NetworkManager:

```bash
nmcli device wifi hotspot ifname wlan0 ssid "MeuHotspot" password "senha"
```

**Falha:** `Connection 'Hotspot' is not available on device wlan0 because device is not available`

Investigando os logs:

```bash
journalctl -u NetworkManager --since "5 minutes ago" | grep -i wlan
```

```
UnknownError: wpa_supplicant couldn't grab this interface
supplicant interface keeps failing, giving up
```

**Causa:** O `wpa_supplicant` (que o NetworkManager usa internamente) não conseguiu assumir o controle da interface `wlan0` para operação como AP. Isso é um comportamento conhecido com drivers SDIO de terceiros que têm integração parcial com as camadas superiores do kernel.

**Solução:** Usar o `hostapd` diretamente com `driver=nl80211`, **bypassing o NetworkManager completamente** para a interface Wi-Fi.

---

## Pré-requisitos

```bash
sudo apt install -y hostapd dnsmasq iptables iptables-persistent
```

---

## Etapa 1 — Parar Serviços Conflitantes

```bash
sudo systemctl stop NetworkManager
sudo systemctl stop wpa_supplicant
sudo pkill -9 wpa_supplicant 2>/dev/null
sudo pkill -9 hostapd 2>/dev/null

sudo ip link set wlan0 down
sleep 1
sudo ip link set wlan0 up
```

> O `wlan0` ficará com `state DOWN` neste momento — isso é **esperado e normal**. O estado operacional do Wi-Fi só muda para UP quando o hostapd inicializar o modo AP. O importante é que a interface esteja presente (`ip link show wlan0`).

---

## Etapa 2 — Atribuir IP Fixo ao wlan0

```bash
sudo ip addr flush dev wlan0
sudo ip addr add 192.168.50.1/24 dev wlan0
sudo ip link set wlan0 up
```

A TV box será o **gateway** da rede do hotspot no endereço `192.168.50.1`.

---

## Etapa 3 — Configurar o hostapd

```bash
sudo tee /etc/hostapd/hostapd.conf << 'EOF'
interface=wlan0
driver=nl80211
ssid=MeuHotspot
hw_mode=g
channel=6
wmm_enabled=0
auth_algs=1
wpa=2
wpa_passphrase=SuaSenhaAqui
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF
```

| Parâmetro | Descrição |
|---|---|
| `driver=nl80211` | Backend padrão moderno do hostapd, compatível com o driver ssv6x5x neste ambiente |
| `hw_mode=g` | 802.11g — 2.4 GHz (único band suportado pelo chip) |
| `channel=6` | Canal 6 (pode ser alterado para 1 ou 11 se houver interferência) |
| `wpa=2` | WPA2 — protocolo de segurança mais seguro disponível |
| `rsn_pairwise=CCMP` | Criptografia AES/CCMP (mais segura que TKIP) |

> **Nota sobre o driver:** A primeira tentativa foi com `driver=wext` (Wireless Extensions, backend legado), que resultou em erro. O driver correto para este ambiente foi `driver=nl80211`. Se ao testar o hostapd aparecer erro com `nl80211`, tente substituir por `wext` — o comportamento pode variar dependendo da versão do driver ssv6x5x instalada.

Apontar o daemon para o arquivo de configuração:

```bash
sudo sed -i 's|#DAEMON_CONF=""|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd
```

### Desmascarar o serviço (necessário no Debian)

O Debian mascara o hostapd por padrão para evitar inicialização sem configuração:

```bash
sudo systemctl unmask hostapd
sudo systemctl enable hostapd
```

### Testar antes de iniciar como serviço

```bash
sudo hostapd -d /etc/hostapd/hostapd.conf
```

Procure pela linha `wlan0: AP-ENABLED` na saída. Se aparecer, o driver aceitou o modo AP. Cancele com `Ctrl+C`.

---

## Etapa 4 — Configurar DHCP com dnsmasq

O dnsmasq distribuirá IPs automaticamente para os dispositivos que se conectarem ao hotspot:

```bash
sudo mv /etc/dnsmasq.conf /etc/dnsmasq.conf.bak 2>/dev/null

sudo tee /etc/dnsmasq.conf << 'EOF'
interface=wlan0
bind-interfaces
dhcp-range=192.168.50.10,192.168.50.100,255.255.255.0,24h
dhcp-option=3,192.168.50.1
dhcp-option=6,8.8.8.8,8.8.4.4
EOF
```

| Parâmetro | Descrição |
|---|---|
| `bind-interfaces` | Garante que o dnsmasq só ouça no wlan0 |
| `dhcp-range` | Faixa de IPs distribuídos: .10 a .100 |
| `dhcp-option=3` | Gateway padrão (a própria TV box) |
| `dhcp-option=6` | Servidores DNS (Google 8.8.8.8 e 8.8.4.4) |

---

## Etapa 5 — Configurar NAT para Compartilhamento de Internet

Para que o tráfego dos clientes Wi-Fi chegue à internet pelo cabo Ethernet:

```bash
# Ativar IP forwarding imediatamente
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward

# Tornar permanente no boot
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

Adicionar regras de NAT no iptables:

```bash
# Mascarar o tráfego saindo pela Ethernet
sudo iptables -t nat -A POSTROUTING -o end0 -j MASQUERADE

# Permitir o encaminhamento entre as interfaces
sudo iptables -A FORWARD -i wlan0 -o end0 -j ACCEPT
sudo iptables -A FORWARD -i end0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

> **Atenção:** A interface Ethernet neste kernel é `end0`, não `eth0`. Usar `eth0` nas regras de iptables causaria falha silenciosa no NAT (tráfego encaminhado mas não mascarado).

Salvar as regras para persistir após reboot:

```bash
sudo netfilter-persistent save
```

---

## Etapa 6 — IP Fixo Persistente no Boot

O IP `192.168.50.1` atribuído ao `wlan0` não persiste automaticamente. Adicione ao `/etc/rc.local`:

```bash
sudo tee /etc/rc.local << 'EOF'
#!/bin/bash
ip addr flush dev wlan0
ip addr add 192.168.50.1/24 dev wlan0
ip link set wlan0 up
exit 0
EOF
sudo chmod +x /etc/rc.local
```

---

## Etapa 7 — Iniciar os Serviços

```bash
sudo systemctl start dnsmasq
sudo systemctl start hostapd
```

---

## Verificação e Testes

### 1 — Verificar status dos serviços

```bash
sudo systemctl status hostapd --no-pager
# Active: active (running)
# wlan0: AP-ENABLED        ← linha mais importante

sudo systemctl status dnsmasq --no-pager
# Active: active (running)
# DHCP, IP range 192.168.50.10 -- 192.168.50.100
```

### 2 — Confirmar modos do chip

```bash
sudo iw phy | grep -A 10 "Supported interface modes"
# * managed
# * AP          ← confirmação de suporte a modo AP
# * AP/VLAN
# * monitor
```

### 3 — Verificar NAT

```bash
sudo iptables -t nat -L POSTROUTING -n -v
# MASQUERADE all -- * end0 0.0.0.0/0 0.0.0.0/0

cat /proc/sys/net/ipv4/ip_forward
# 1
```

### 4 — Teste real com dispositivo

1. Em um celular ou notebook, abra as configurações de Wi-Fi
2. Localize a rede com o SSID configurado (`MeuHotspot` por padrão)
3. Conecte com a senha definida em `wpa_passphrase`
4. Verifique se recebeu um IP no range `192.168.50.10–100`
5. Com o cabo Ethernet conectado na TV box, acesse qualquer site — a internet deve funcionar

### 5 — Ver clientes conectados

```bash
# Leases DHCP ativos
cat /var/lib/misc/dnsmasq.leases
# 1782339943 14:b5:cd:88:f4:27 192.168.50.73 pop-os ...

# Clientes autenticados no AP
sudo hostapd_cli all_sta
```

---

## Resultado Final Confirmado

| Item | Status | Detalhe |
|---|---|---|
| AP no ar | ✅ | hostapd com driver=wext |
| SSID visível | ✅ | Aparece na lista de redes Wi-Fi |
| Clientes conectando | ✅ | Notebook pop-os recebeu 192.168.50.73 |
| DHCP funcionando | ✅ | dnsmasq distribuindo IPs |
| Ping da TV box | ✅ | 0% packet loss para 8.8.8.8 |
| Internet nos clientes | ✅ | NAT via iptables MASQUERADE em end0 |
| Serviços no boot | ✅ | hostapd e dnsmasq habilitados |
| ip_forward persistente | ✅ | /etc/sysctl.conf + netfilter-persistent |

---

## Observações Importantes

**Modo simultâneo STA + AP não é suportado.** O chip SSV6501P tem rádio único. Se o `wlan0` estiver operando como AP, não pode simultaneamente se conectar a outra rede Wi-Fi como cliente. Por isso a topologia deste projeto usa obrigatoriamente o cabo Ethernet (`end0`) como entrada de internet.

**Troca de SSID e senha.** Para alterar as configurações do hotspot após a instalação:

```bash
sudo nano /etc/hostapd/hostapd.conf
# Edite ssid= e wpa_passphrase=
sudo systemctl restart hostapd
```

---

## Referências

- [hostapd documentation](https://w1.fi/hostapd/)
- [dnsmasq documentation](https://thekelleys.org.uk/dnsmasq/doc.html)
- [Linux iptables NAT](https://netfilter.org/documentation/)
- [Armbian Forum — RK322x AP configuration](https://forum.armbian.com/topic/34923-csc-armbian-for-rk322x-tv-box-boards/)
