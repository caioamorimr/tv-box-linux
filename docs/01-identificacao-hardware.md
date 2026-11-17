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
| Chip Wi-Fi (variante 3) | Realtek RTL8723BS — barramento SDIO |
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

## Identificar o chip Wi-Fi antes de instalar drivers

Este é o passo mais importante. Mesmo dentro da família RK322x, o chip Wi-Fi varia entre fabricantes e lotes de produção, e o driver errado faz o chip falhar sem mensagem clara. Três variantes já apareceram em campo: Realtek RTL8723BS, RSV6200A e SSV6501P / SV6256P.

### Por que não dá para usar o `ssv6051` como sonda

Carregar o `ssv6051` parece o caminho óbvio, mas ele falha com a mesma saída nos dois chips SSV (`Please redefine xtal_clock(wifi.cfg)!!` seguido de `Failed to initialize device`). Como o resultado é idêntico, ele não diz qual chip está presente.

Quem lê o Chip ID de verdade é o `ssv6x5x`. Ele imprime a string exata do chip e inicializa com sucesso, ou rejeita o chip com erro -22 quando ele não é da família SSV6X5X. Por isso a sondagem usa o `ssv6x5x`, compilado via DKMS, mesmo nas unidades que no fim usam o `ssv6051`.

> Não procure o texto `RSV6200` no dmesg. A string de chip que aparece nos logs é `SSV6200Ax-...`, nunca `RSV6200x`. "RSV6200A" é só o nome adotado para essa família. Uma checagem de texto em cima desse nome identifica o chip errado.

### Ordem de checagem

1. Realtek primeiro. O driver nativo `r8723bs` se liga sozinho ao dispositivo quando o SDIO é enumerado, bem antes de qualquer script rodar, e deixa rastro no dmesg:

```bash
dmesg | grep -i rtl8723bs
```

2. Se não for Realtek, instale o `ssv6x5x` via DKMS (doc 03) e carregue:

```bash
sudo modprobe ssv6x5x
sleep 4
dmesg | grep -iE "CHIP ID:|error -22"
sudo rmmod ssv6x5x
```

### Interpretando o resultado

| O que aparece no dmesg | Chip | Driver correto | Documentação |
|---|---|---|---|
| `rtl8723bs` sem você ter carregado nada | Realtek RTL8723BS | `r8723bs` (nativo) | este documento |
| `CHIP ID: SSV6006C0` (ou outro `SSV...`) e inicialização bem-sucedida | SSV6501P / SV6256P | `ssv6x5x` (DKMS) | `03-driver-wifi-ssv6x5x.md` |
| `probe with driver ssv6x5x failed with error -22` | RSV6200A | `ssv6051` (nativo) | `03b-driver-wifi-rsv6200a.md` |

> O script `01-install-wifi-driver.sh` faz essa detecção automaticamente.

---

## Variantes de chip Wi-Fi conhecidas no RK322x

| Chip | Driver | Compilação | Firmware externo |
|---|---|---|---|
| SSV6501P / SV6256P (família SSV6X5X) | `ssv6x5x` | Via DKMS | Necessário (`ssv6x5x-sw.bin` e `ssv6x5x-wifi.cfg`) |
| RSV6200A | `ssv6051` | Nativo no kernel | `ssv6051-sw.bin`: já vem no Armbian; em imagens montadas do zero, instale à parte (doc 03b) |
| Realtek RTL8723BS | `r8723bs` | Nativo no kernel | Necessário: pacote `firmware-realtek` |

Todos os chips:
- Conectam ao SoC pelo barramento SDIO (não USB, então não aparecem no `lsusb`).
- Não têm suporte no kernel mainline sem configuração adicional (no caso dos SSV).
- Os dois drivers SSV conflitam se carregarem ao mesmo tempo, então o blacklist é obrigatório.

### Realtek RTL8723BS e o firmware

Sem o pacote `firmware-realtek`, o `r8723bs` carrega e a `wlan0` aparece, mas o rádio nunca recebe firmware (`Direct firmware load ... failed with error -2`). O AP fica no ar sem transmitir nada, e nenhum serviço de rede reclama.

```bash
sudo apt install firmware-realtek
```

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
│  │ SSV6501P,   │  │ Ethernet  │     │
│  │ RSV6200A ou │  │  (end0)   │     │
│  │ RTL8723BS   │  │           │     │
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