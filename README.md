# TV Box Linux — RK322x

> Documentação completa do processo de **descaracterização de TV Box** com chip Rockchip RK322x: instalação do Armbian/Debian, ativação do driver Wi-Fi SSV6X5X em kernel moderno e configuração de Access Point com compartilhamento de internet.

---

## Sumário

- [Sobre o Projeto](#sobre-o-projeto)
- [Hardware](#hardware)
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

Este projeto documenta o processo de **reaproveitar uma TV Box genérica**, originalmente rodando Android, como um servidor Linux funcional com Access Point Wi-Fi, transformando hardware descartado em infraestrutura de rede útil.

O principal desafio técnico foi fazer o **chip Wi-Fi onboard funcionar em kernel moderno (6.x)**: o driver original do fabricante foi escrito exclusivamente para o kernel 4.4 legado e não compila em versões superiores. A solução envolveu identificar o conflito de módulos no barramento SDIO, compilar um port comunitário do driver via DKMS e contornar limitações do wpa_supplicant com nl80211.

---

## Hardware

| Componente | Especificação |
|---|---|
| **SoC** | Rockchip RK3228A (família RK322x) |
| **Arquitetura** | ARMv7l — 32 bits (Cortex-A7) |
| **Chip Wi-Fi** | SSV6501P / SV6256P (família SSV6X5X, barramento SDIO) |
| **Ethernet** | Embutida no SoC — interface `end0` (driver stmmac) |
| **RAM** | ~1 GB DDR3 |
| **Armazenamento interno** | eMMC (Android de fábrica — mantido intacto) |
| **Boot** | Cartão microSD (sistema Linux) |
| **Sistema Operacional** | Armbian 26.8.0 — Debian 13 "Trixie" Minimal |
| **Kernel** | 6.18.36-current-rockchip |

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

A TV Box recebe internet pelo cabo Ethernet (`end0`) e compartilha via Wi-Fi (`wlan0`) como Access Point, com NAT e DHCP para os clientes.

---

## Pré-requisitos

- TV Box com SoC **Rockchip RK322x** (RK3228A ou RK3229)
- Cartão **microSD** de pelo menos 8 GB
- Cabo **Ethernet** conectado à TV Box (necessário para o compartilhamento de internet)
- PC para gravar a imagem
- Acesso **SSH** à TV Box após o primeiro boot

---

## Quick Start

> Para quem quer reproduzir o projeto do zero, com os mesmos resultados.

### 1 — Instalar o Armbian

Baixe o **Armbian Imager** em [imager.armbian.com](https://imager.armbian.com), selecione a placa `rk322x-box`, escolha a imagem **Debian 13 Minimal** e grave no cartão microSD. Configure usuário, senha e Wi-Fi no Autoconfig Profile antes de gravar.

Insira o cartão na TV Box e ligue. Aguarde o primeiro boot (~2-3 min) e acesse via SSH.

### 2 — Instalar o driver Wi-Fi

```bash
# Na TV Box, via SSH
git clone https://github.com/caioamorimr/tv-box-linux.git
cd tv-box-linux
sudo bash scripts/01-install-wifi-driver.sh
sudo reboot
```

Após o reboot, confirme:

```bash
ip link show wlan0
# Esperado: state UP
```

### 3 — Configurar o Access Point

Edite as variáveis no topo do script (SSID, senha, canal):

```bash
nano scripts/02-setup-ap.sh
```

Execute:

```bash
sudo bash scripts/02-setup-ap.sh
```

O hotspot estará no ar imediatamente. Conecte um dispositivo à rede configurada e acesse a internet.

---

## Estrutura do Repositório

```
tv-box-linux/
├── README.md
│
├── docs/
│   ├── 01-identificacao-hardware.md   ← SoC, chip Wi-Fi, como identificar
│   ├── 02-instalacao-armbian.md       ← Imager, gravação, primeiro boot
│   ├── 03-driver-wifi-ssv6x5x.md     ← Causa raiz, DKMS, blacklist
│   └── 04-access-point.md            ← hostapd, dnsmasq, NAT, iptables
│
├── configs/
│   ├── hostapd.conf                   ← Configuração do Access Point
│   ├── dnsmasq.conf                   ← Configuração do DHCP
│   ├── blacklist-ssv6051.conf         ← Blacklist do módulo conflitante
│   ├── ssv6x5x.conf                   ← Paths do firmware do driver
│   ├── ssv6x5x-wifi.cfg              ← Firmware de configuração do chip
│   ├── sysctl.conf                    ← IP forwarding persistente
│   └── rc.local                       ← IP fixo do wlan0 no boot
│
└── scripts/
    ├── 01-install-wifi-driver.sh      ← Instalação automatizada do driver
    └── 02-setup-ap.sh                 ← Configuração automatizada do AP
```

---

## Documentação Detalhada

Cada etapa do projeto está documentada em detalhes na pasta `docs/`:

| Arquivo | Conteúdo |
|---|---|
| [01 — Identificação do Hardware](docs/01-identificacao-hardware.md) | Como identificar o SoC RK322x e o chip Wi-Fi SSV6X5X; diagrama do hardware |
| [02 — Instalação do Armbian](docs/02-instalacao-armbian.md) | Escolha da imagem, gravação com Armbian Imager, Autoconfig Profile, primeiro boot |
| [03 — Driver Wi-Fi SSV6X5X](docs/03-driver-wifi-ssv6x5x.md) | Causa raiz do problema (`calibration fail`), compilação via DKMS, blacklist do `ssv6051` |
| [04 — Access Point](docs/04-access-point.md) | hostapd com nl80211, dnsmasq, NAT via iptables, ip_forward, persistência no boot |

---

## Resultado Final

| Componente | Status |
|---|---|
| Armbian/Debian 13 rodando do cartão SD | ✅ |
| Driver SSV6X5X instalado via DKMS | ✅ |
| `wlan0` em estado UP após o boot | ✅ |
| Access Point Wi-Fi WPA2 no ar | ✅ |
| Clientes recebendo IP via DHCP | ✅ |
| Internet compartilhada via NAT (Ethernet → Wi-Fi) | ✅ |
| Configurações persistindo após reboot | ✅ |
| Driver recompilado automaticamente em updates de kernel | ✅ |

---

## Problemas Conhecidos e Soluções

### `wlan0` em estado DOWN após o boot

**Causa:** O módulo `ssv6051` (errado) carregava antes do `ssv6x5x` (correto) e corrompia o estado do chip no barramento SDIO.

**Solução:** Blacklist permanente do `ssv6051` com atualização do initramfs:

```bash
echo "blacklist ssv6051" | sudo tee /etc/modprobe.d/blacklist-ssv6051.conf
sudo update-initramfs -u
sudo reboot
```

---

### `RTNETLINK answers: Operation not permitted` ao subir `wlan0`

Sintoma do mesmo problema acima — o módulo errado havia bloqueado o barramento SDIO. A solução é a mesma.

---

### `nmcli device wifi hotspot` falha com "device not available"

**Causa:** O `wpa_supplicant` não consegue assumir o controle do `wlan0` via NetworkManager com este driver.

**Solução:** Usar o `hostapd` diretamente (veja o script `02-setup-ap.sh`).

---

## Referências

- [Armbian — rk322x-box](https://www.armbian.com/rk322x-box/)
- [Fórum Armbian — CSC Armbian for RK322x TV box boards](https://forum.armbian.com/topic/34923-csc-armbian-for-rk322x-tv-box-boards/)
- [Driver SSV6X5X para kernel 6.x — cdhigh/armbian_sv6256p](https://github.com/cdhigh/armbian_sv6256p)
- [Driver SSV6X5X original RK322x — paolosabatino/ssv6x5x](https://github.com/paolosabatino/ssv6x5x)
- [Fórum Armbian — SV6256P WiFi working on Linux 6.x](https://forum.armbian.com/topic/57960-sv6256p-wifi-now-working-on-linux-6x-armbian-tested/)
- [hostapd documentation](https://w1.fi/hostapd/)
- [dnsmasq documentation](https://thekelleys.org.uk/dnsmasq/doc.html)