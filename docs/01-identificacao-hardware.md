# 01 — Identificação do Hardware

## Visão Geral

O primeiro desafio ao trabalhar com TV Boxes genéricas é identificar com precisão o hardware presente na placa, informação que os fabricantes raramente documentam. Esta etapa é fundamental porque determina quais imagens são compatíveis, quais drivers são necessários e quais limitações existem.

---

## Dispositivo Utilizado

| Componente | Identificação |
|---|---|
| SoC (System on Chip) | Rockchip RK3228A (família RK322x) |
| Arquitetura | ARMv7l — 32 bits (Cortex-A7) |
| Chip Wi-Fi (variante 1) | SSV6501P / SV6256P (família SSV6X5X) — barramento SDIO |
| Chip Wi-Fi (variante 2) | RSV6200A (Rockchip South Valley) — barramento SDIO |
| Interface Ethernet | Embutida no SoC (driver stmmac) — identificada como `end0` |
| Memória RAM | ~1 GB DDR3 |
| Armazenamento interno | eMMC (continha Android de fábrica) |
| Armazenamento externo | Slot microSD (utilizado para instalação inicial) |
| Kernel em uso | 6.18.x-current-rockchip |
| Sistema Operacional | Armbian 26.8.0 (base Debian 13 "Trixie") |

---

## Como Identificar o SoC RK322x

### Método 1 — Pelo Android original

Acesse **Configurações → Sobre o dispositivo**. Geralmente aparece o modelo da placa ou o SoC na linha "Modelo" ou "Hardware".

### Método 2 — Pelo hostname padrão do Armbian legado

Se o dispositivo já teve Armbian anteriormente, o hostname costuma ser `rk322x` ou `rk322a`, refletindo diretamente o SoC.

### Método 3 — Pelo kernel em execução

```bash
uname -r
# 6.18.36-current-rockchip  ← confirma plataforma rockchip

cat /proc/device-tree/model

cat /etc/os-release | head -5
# PRETTY_NAME="Armbian_community 26.8.0-trunk.170 trixie"
```

---

## ⚠️ Identificar o Chip Wi-Fi ANTES de Instalar Drivers

Este é o passo mais importante. Mesmo dentro da família RK322x, o chip Wi-Fi varia entre fabricantes e lotes de produção. O driver errado faz o chip falhar silenciosamente.

**Execute antes de qualquer instalação:**

```bash
# Carregar temporariamente o ssv6051 (nativo, sempre disponível no kernel)
sudo modprobe ssv6051
sleep 3

# Ler o Chip ID
dmesg | grep -i "chip id" | tail -1
```

### Interpretando o resultado

| Saída do dmesg | Chip | Driver correto | Documentação |
|---|---|---|---|
| `CHIP ID: RSV6200A0-...` | RSV6200A | `ssv6051` (nativo) | `03b-driver-wifi-rsv6200a.md` |
| `CHIP ID: SSV6006C0` ou similar | SSV6501P / SV6256P | `ssv6x5x` (compilar via DKMS) | `03-driver-wifi-ssv6x5x.md` |

> O script `01-install-wifi-driver.sh` já faz essa detecção automaticamente.

---

## Variantes de Chip Wi-Fi Conhecidas no RK322x

| Chip | Driver | Compilação | Firmware externo |
|---|---|---|---|
| SSV6501P / SV6256P (família SSV6X5X) | `ssv6x5x` | ✅ Via DKMS | ✅ Necessário |
| RSV6200A (Rockchip South Valley) | `ssv6051` | ❌ Nativo no kernel | ❌ Não necessário |

**Ambos os chips:**
- Conectam ao SoC via barramento **SDIO** (não USB — invisíveis ao `lsusb`)
- Não possuem suporte no kernel mainline sem configuração adicional
- Conflitam entre si se os dois drivers carregarem simultaneamente — blacklist é obrigatório

---

## Como Identificar Interfaces de Rede

```bash
ip link show
```

```
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: end0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...    ← Ethernet
3: wlan0: <BROADCAST,MULTICAST> ...               ← Wi-Fi (requer driver configurado)
```

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
│         │ SDIO        │ GMAC        │
│  ┌──────▼──────┐  ┌───▼───────┐     │
│  │ SSV6501P    │  │ Ethernet  │     │
│  │ ou RSV6200A │  │  (end0)   │     │
│  │ Wi-Fi 2.4G  │  │           │     │
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
- [Driver SSV6X5X para kernel 6.x — cdhigh/armbian_sv6256p](https://github.com/cdhigh/armbian_sv6256p)