# TV Box Linux — RK322x

> Documentação completa do processo de **descaracterização de TV Box** com chip Rockchip RK322x: instalação do Armbian/Debian, ativação do driver Wi-Fi e configuração de Access Point com compartilhamento de internet.

---

## Sumário

- [Sobre o Projeto](#sobre-o-projeto)
- [Hardware](#hardware)
- [Variantes de Chip Wi-Fi](#variantes-de-chip-wi-fi)
- [Topologia Final](#topologia-final)
- [Pré-requisitos](#pré-requisitos)
- [Quick Start](#quick-start)
- [Estrutura do Repositório](#estrutura-do-repositório)
- [Documentação Detalhada](#documentação-detalhada)
- [Resultado Final](#resultado-final)
- [Problemas Conhecidos e Soluções](#problemas-conhecidos-e-soluções)
- [Referências](#referências)

---

## Sobre o Projeto

Este projeto documenta o processo de **reaproveitar TV Boxes genéricas**, originalmente rodando Android, como servidores Linux com Access Point Wi-Fi, transformando hardware descartado em infraestrutura de rede útil.

Os principais desafios técnicos foram:

1. **Driver Wi-Fi em kernel moderno (6.x):** o driver original do fabricante foi escrito exclusivamente para o kernel 4.4 legado. A solução envolveu detecção automática do chip presente, compilação via DKMS para o chip SSV6X5X, ou uso do driver nativo para o chip RSV6200A.

2. **Variação de hardware:** TV boxes com SoC RK322x aparentemente idênticas por fora podem conter chips Wi-Fi diferentes internamente.

3. **Interferência do NetworkManager:** em alguns casos o NM conectava o `wlan0` como cliente Wi-Fi, impedindo o hostapd de operar em modo AP.

---

## Hardware

| Componente | Especificação |
|---|---|
| **SoC** | Rockchip RK3228A (família RK322x) |
| **Arquitetura** | ARMv7l — 32 bits (Cortex-A7) |
| **Ethernet** | Embutida no SoC — interface `end0` (driver stmmac) |
| **RAM** | ~1 GB DDR3 |
| **Armazenamento interno** | eMMC (Android de fábrica — substituído pelo Linux) |
| **Sistema Operacional** | Armbian 26.8.0 — Debian 13 "Trixie" Minimal |
| **Kernel** | 6.18.x-current-rockchip |

---

## Variantes de Chip Wi-Fi

> ⚠️ **Importante:** mesmo dentro da família RK322x, o chip Wi-Fi pode variar entre unidades. Identifique o chip antes de instalar qualquer driver.

```bash
sudo modprobe ssv6051 && sleep 3
dmesg | grep -i "chip id" | tail -1
```

| Saída | Chip | Driver | Compilação |
|---|---|---|---|
| `CHIP ID: RSV6200A0-...` | RSV6200A | `ssv6051` (nativo) | ❌ Não necessária |
| `CHIP ID: SSV6006C0` ou similar | SSV6501P / SV6256P | `ssv6x5x` (externo) | ✅ Via DKMS |

O script `01-install-wifi-driver.sh` detecta automaticamente o chip e instala o driver correto.

---

## Topologia Final

```
         Internet
            │
            │ cabo Ethernet
            ▼
    ┌───────────────┐
    │  end0 (eth)   │
    │               │
    │  TV Box       │   192.168.50.1
    │  RK322x       │
    │               │
    │  wlan0 (AP)   │
    └───────┬───────┘
            │ Wi-Fi 2.4 GHz (WPA2)
    ┌───────┴────────────────┐
    ▼           ▼            ▼
 Notebook    Celular      Tablet
.50.10~.100  via DHCP     via DHCP
```

---

## Pré-requisitos

- TV Box com SoC **Rockchip RK322x** (RK3228A ou RK3229)
- Cartão **microSD** de pelo menos 8 GB (para instalação inicial)
- Cabo **Ethernet** conectado à TV Box
- Acesso **SSH** à TV Box após o primeiro boot

---

## Quick Start

### 1 — Instalar o Armbian

Baixe o **Armbian Imager** em [imager.armbian.com](https://imager.armbian.com), selecione `rk322x-box`, escolha **Debian 13 Minimal** e grave no microSD com o Autoconfig Profile configurado (usuário, senha, Wi-Fi, timezone).

### 2 — Clonar o repositório na TV Box

```bash
git clone https://github.com/caioamorimr/tv-box-linux.git
cd tv-box-linux
```

### 3 — Instalar o driver Wi-Fi

```bash
sudo bash scripts/01-install-wifi-driver.sh
sudo reboot
```

O script detecta automaticamente o chip (RSV6200A ou SSV6X5X) e instala o driver correto. Após o reboot:

```bash
ip link show wlan0
# Esperado: state UP
```

### 4 — Configurar o Access Point

Edite as variáveis no topo do script:

```bash
nano scripts/02-setup-ap.sh
# Ajuste: SSID, PASSPHRASE, CHANNEL, AP_IP, WAN_IFACE
```

Execute:

```bash
sudo bash scripts/02-setup-ap.sh
```

### 5 — Instalar na eMMC (permanente)

```bash
sudo armbian-config
# System → Storage → TO001 (Copy running system)
# Selecione eMMC → Boot from eMMC → ext4
# Power off → remova o SD → ligue
```

---

## Estrutura do Repositório

```
tv-box-linux/
├── README.md
│
├── docs/
│   ├── 01-identificacao-hardware.md    ← SoC, chips Wi-Fi, como identificar
│   ├── 02-instalacao-armbian.md        ← Imager, gravação, primeiro boot
│   ├── 03-driver-wifi-ssv6x5x.md      ← Chip SSV6501P: DKMS, blacklist ssv6051
│   ├── 03b-driver-wifi-rsv6200a.md    ← Chip RSV6200A: driver nativo ssv6051
│   └── 04-access-point.md             ← hostapd, dnsmasq, NAT, iptables
│
├── configs/
│   ├── hostapd.conf                    ← Configuração do Access Point
│   ├── dnsmasq.conf                    ← Configuração do DHCP
│   ├── blacklist-ssv6051.conf          ← Blacklist para TV boxes com SSV6X5X
│   ├── blacklist-ssv6x5x.conf         ← Blacklist para TV boxes com RSV6200A
│   ├── ssv6x5x.conf                    ← Paths do firmware do driver SSV6X5X
│   ├── ssv6x5x-wifi.cfg               ← Firmware de configuração do chip
│   ├── 99-ip-forward.conf             ← IP forwarding persistente (sysctl.d)
│   └── rc.local                        ← IP fixo + ordem de boot dos serviços
│
└── scripts/
    ├── 01-install-wifi-driver.sh       ← Detecção de chip + instalação automática
    └── 02-setup-ap.sh                  ← Configuração completa do AP
```

---

## Documentação Detalhada

| Arquivo | Conteúdo |
|---|---|
| [01 — Identificação do Hardware](docs/01-identificacao-hardware.md) | Como identificar SoC e chip Wi-Fi; variantes RSV6200A vs SSV6X5X |
| [02 — Instalação do Armbian](docs/02-instalacao-armbian.md) | Escolha da imagem, gravação, Autoconfig Profile, primeiro boot |
| [03 — Driver SSV6X5X](docs/03-driver-wifi-ssv6x5x.md) | Chip SSV6501P/SV6256P: compilação via DKMS, blacklist do ssv6051 |
| [03b — Driver RSV6200A](docs/03b-driver-wifi-rsv6200a.md) | Chip RSV6200A: driver nativo ssv6051, blacklist do ssv6x5x |
| [04 — Access Point](docs/04-access-point.md) | hostapd, dnsmasq, NAT, ip_forward, NM unmanaged, timing de boot |

---

## Resultado Final

| Componente | Status |
|---|---|
| Armbian/Debian 13 instalado na eMMC | ✅ |
| Detecção automática do chip Wi-Fi | ✅ |
| Driver SSV6X5X instalado via DKMS | ✅ |
| Driver RSV6200A (ssv6051) nativo funcionando | ✅ |
| `wlan0` em estado UP após o boot | ✅ |
| Access Point Wi-Fi WPA2 no ar | ✅ |
| Clientes recebendo IP via DHCP | ✅ |
| Internet compartilhada via NAT | ✅ |
| NetworkManager bloqueado de interferir no wlan0 | ✅ |
| ip_forward persistente via sysctl.d | ✅ |
| Ordem correta de inicialização no boot (rc.local) | ✅ |
| Driver recompilado automaticamente em updates de kernel (DKMS) | ✅ |

---

## Problemas Conhecidos e Soluções

### `wlan0` em estado DOWN após o boot

**Causa:** Módulo conflitante (`ssv6051` ou `ssv6x5x`) carregando antes do driver correto e corrompendo o estado do chip no barramento SDIO.

**Diagnóstico:**
```bash
dmesg | grep -i "chip id"     # identificar o chip
lsmod | grep ssv              # ver qual módulo está carregado
```

**Solução:** Aplicar o blacklist correto para o chip presente e atualizar o initramfs. O script `01-install-wifi-driver.sh` faz isso automaticamente.

---

### Rede do hotspot não aparece para outros dispositivos

**Causa mais comum:** NetworkManager conectou o `wlan0` como cliente em uma rede Wi-Fi local, impedindo o hostapd de operar em modo AP.

**Diagnóstico:**
```bash
iw dev wlan0 info
# Se mostrar "type managed" e "ssid <nome_de_rede>", o NM tomou a interface
```

**Solução:**
```bash
sudo tee /etc/NetworkManager/conf.d/unmanaged-wlan0.conf << 'EOF'
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
sudo systemctl restart NetworkManager
sudo systemctl restart hostapd
```

---

### dnsmasq falha com "unknown interface wlan0"

**Causa:** O dnsmasq iniciou antes do `wlan0` estar configurado com IP — problema de timing no boot.

**Solução:** O `rc.local` deve reiniciar o dnsmasq **depois** de configurar o IP no `wlan0`. Já está incluído no script `02-setup-ap.sh`.

---

### ip_forward volta a 0 após reboot

**Causa:** O `/etc/sysctl.conf` é processado tarde demais no boot pelo Armbian.

**Solução:**
```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

---

### Erro de headers no DKMS: "cannot be found at /lib/modules/.../build"

**Causa:** Versão do kernel diferente da versão dos headers instalados.

**Solução:**
```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
# Rodar o script novamente após o reboot
```

---

## Referências

- [Armbian — rk322x-box](https://www.armbian.com/rk322x-box/)
- [Fórum Armbian — CSC Armbian for RK322x TV box boards](https://forum.armbian.com/topic/34923-csc-armbian-for-rk322x-tv-box-boards/)
- [Driver SSV6X5X para kernel 6.x — cdhigh/armbian_sv6256p](https://github.com/cdhigh/armbian_sv6256p)
- [Driver SSV6X5X original RK322x — paolosabatino/ssv6x5x](https://github.com/paolosabatino/ssv6x5x)
- [Fórum Armbian — SV6256P WiFi working on Linux 6.x](https://forum.armbian.com/topic/57960-sv6256p-wifi-now-working-on-linux-6x-armbian-tested/)
- [hostapd documentation](https://w1.fi/hostapd/)
- [dnsmasq documentation](https://thekelleys.org.uk/dnsmasq/doc.html)