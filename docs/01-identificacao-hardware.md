# 01 — Identificação do Hardware

## Visão Geral

O primeiro desafio ao trabalhar com TV Boxes genéricas é identificar com precisão o hardware presente na placa — informação que os fabricantes raramente documentam de forma clara. Esta etapa é fundamental porque determina quais imagens de sistema operacional são compatíveis, quais drivers são necessários e quais limitações existem.

---

## Dispositivo Utilizado

| Componente | Identificação |
|---|---|
| SoC (System on Chip) | Rockchip RK3228A (família RK322x) |
| Arquitetura | ARMv7l — 32 bits (Cortex-A7) |
| Chip Wi-Fi | SSV6501P / SV6256P (família SSV6X5X) — barramento SDIO |
| Interface Ethernet | Embutida no SoC (driver stmmac), identificada como `end0` |
| Memória RAM | ~1 GB DDR3 |
| Armazenamento interno | eMMC (continha Android de fábrica) |
| Armazenamento externo | Slot microSD (utilizado para o Linux) |
| Kernel em uso | 6.18.36-current-rockchip |
| Sistema Operacional | Armbian 26.8.0 (base Debian 13 "Trixie") |

---

## Como Identificar o SoC RK322x

Em dispositivos sem documentação pública, o SoC pode ser identificado por três métodos:

### Método 1 — Pelo Android original (antes de instalar Linux)

Acesse **Configurações → Sobre o dispositivo** no Android. Geralmente aparece o modelo da placa ou o SoC na linha "Modelo" ou "Hardware".

### Método 2 — Pelo hostname padrão do Armbian legado

Se o dispositivo já tiver sido usado com Armbian anteriormente, o hostname padrão gerado costuma ser `rk322x` ou `rk322a`, refletindo diretamente o SoC. No caso deste projeto, o hostname encontrado foi `rk322a`, confirmando a família RK322x.

### Método 3 — Pelo kernel em execução no Linux

```bash
# Versão do kernel (confirma a plataforma rockchip)
uname -r
# Saída: 6.18.36-current-rockchip

# Modelo da placa via Device Tree
cat /proc/device-tree/model

# Informações do processador
cat /proc/cpuinfo | grep -E "Hardware|Processor"

# Sistema operacional
cat /etc/os-release | head -5
# Saída:
# PRETTY_NAME="Armbian_community 26.8.0-trunk.170 trixie"
# NAME="Debian GNU/Linux"
# VERSION_ID="13"
```

---

## Identificação do Chip Wi-Fi SSV6X5X

O chip Wi-Fi é **integrado à placa via barramento SDIO** (não é um adaptador USB removível), tornando-o invisível ao comando `lsusb`. Para identificá-lo:

```bash
# Verificar qual módulo de driver está sendo carregado
lsmod | grep -i ssv

# Ver mensagens do kernel sobre o chip no boot
dmesg | grep -iE "ssv|sdio|wlan"

# Listar interfaces de rede
ip link show
```

Saída esperada do `lsmod` após o driver correto estar instalado:

```
ssv6x5x   512000  0
mac80211   864256  1 ssv6x5x
cfg80211   757760  2 mac80211,ssv6x5x
```

### A Família SSV6X5X

Os chips da família SSV6X5X (também grafados SSV6200, SSV6051, SV6152P, SV6256P, SSV6501P) são produzidos pela **iComm Semiconductor (South Silicon Valley)**. Compartilham o mesmo driver de base e são extremamente comuns em TV Boxes genéricas chinesas baseadas em Rockchip RK322x.

**Características críticas para o Linux:**

- Conectam ao SoC via barramento **SDIO** (não USB)
- O driver original do fabricante foi escrito exclusivamente para o kernel **4.4 (legado Rockchip)**
- **Não há suporte nativo no kernel mainline** — o chip é invisível sem driver externo
- O Armbian inclui no kernel um módulo chamado `ssv6051` que **não é compatível** com o SSV6501P/SV6256P e causa conflito grave se carregado simultaneamente

---

## Interfaces de Rede Identificadas

```bash
ip link show
```

```
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: end0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...    ← Ethernet
3: wlan0: <BROADCAST,MULTICAST> ...               ← Wi-Fi (requer driver externo)
```

> **Atenção:** A interface Ethernet aparece como `end0` (não `eth0`) neste kernel. Este detalhe é importante ao configurar regras de firewall, NAT e roteamento.

---

## Diagrama do Hardware

```
┌─────────────────────────────────────┐
│           TV Box RK322x             │
│                                     │
│  ┌────────────────────────────┐     │
│  │    SoC Rockchip RK3228A    │     │
│  │    ARMv7l  Cortex-A7       │     │
│  │    32-bit, até 1.4 GHz     │     │
│  └──────┬─────────────┬───────┘     │
│         │ SDIO         │ GMAC       │
│  ┌──────▼──────┐  ┌────▼──────┐     │
│  │  SSV6501P   │  │ Ethernet  │     │
│  │  Wi-Fi      │  │  (end0)   │     │
│  │  2.4 GHz    │  │           │     │
│  └─────────────┘  └───────────┘     │
│                                     │
│  ┌──────────┐    ┌──────────────┐   │
│  │   eMMC   │    │  Slot microSD│   │
│  │ (Android)│    │   (Linux)    │   │
│  └──────────┘    └──────────────┘   │
└─────────────────────────────────────┘
```

---

## Referências

- [Armbian — Supported Boards: rk322x-box](https://www.armbian.com/rk322x-box/)
- [Fórum Armbian — CSC Armbian for RK322x TV box boards](https://forum.armbian.com/topic/34923-csc-armbian-for-rk322x-tv-box-boards/)
- [Driver comunitário SSV6X5X para kernel 6.x](https://github.com/cdhigh/armbian_sv6256p)
