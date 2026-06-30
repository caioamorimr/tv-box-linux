# 03b — Driver Wi-Fi RSV6200A no Debian/Armbian (RK322x)

## Visão Geral

Durante o processo de instalação em múltiplas TV boxes com SoC RK322x, foi descoberto que **hardware aparentemente idêntico por fora pode conter chips Wi-Fi diferentes internamente**. Esta segunda variante — o **RSV6200A** — usa o driver `ssv6051`, que já está presente no kernel do Armbian, tornando desnecessária qualquer compilação de driver externo.

---

## Ambiente

| Item | Valor |
|---|---|
| Hardware | TV Box RK3228A (RK322x) |
| Chip Wi-Fi | RSV6200A (Rockchip South Valley, barramento SDIO) |
| Sistema | Armbian 26.8.0 — Debian 13 Trixie |
| Kernel | 6.18.37-current-rockchip |
| Arquitetura | ARMv7l (32-bit) |
| Driver utilizado | `ssv6051` — **nativo no kernel, sem compilação** |

---

## Como Identificar o Chip RSV6200A

Antes de instalar qualquer driver, identifique qual chip está presente:

```bash
# Carregar temporariamente o ssv6051 (nativo, sempre disponível)
sudo modprobe ssv6051
sleep 3

# Ler o Chip ID do dmesg
dmesg | grep -i "chip id" | tail -1
```

Saída esperada para RSV6200A:
```
ssv6200: chip id: RSV6200A0-201311, tag: 2014012420010960
```

Saída esperada para SSV6501P/SV6256P (ver doc 03):
```
TU_SSV6XXX_SDIO: CHIP ID: SSV6006C0
```

> Se aparecer `RSV6200A`, siga este documento.
> Se aparecer outro ID, siga o documento `03-driver-wifi-ssv6x5x.md`.

---

## Diferença Entre os Chips

| Característica | RSV6200A | SSV6501P / SV6256P |
|---|---|---|
| Fabricante | Rockchip South Valley | iComm Semiconductor |
| Driver | `ssv6051` (nativo) | `ssv6x5x` (externo, via DKMS) |
| Compilação necessária | ❌ Não | ✅ Sim |
| Firmware externo | ❌ Não (`ssv6051-sw.bin` já no kernel) |✅ Sim |
| Conflito com outro driver | `ssv6x5x` causa conflito | `ssv6051` causa conflito |

---

## O Problema

Ao rodar o script `01-install-wifi-driver.sh` em uma TV box com RSV6200A, o DKMS tentou compilar o `ssv6x5x` para esta variante, o que desnecessariamente instalou o driver errado. O `ssv6x5x` carregava e tentava inicializar o chip RSV6200A, mas falhava:

```bash
dmesg | grep -i ssv
```

```
ssv6x5x RSV6200A: Failed to initialize device
ssv6x5x RSV6200A: probe with driver ssv6x5x failed with error -22
```

**Causa raiz:** O `ssv6x5x` não reconhece o chip RSV6200A. O driver correto para este chip é o `ssv6051`, que já está embutido no kernel do Armbian.

---

## Solução Manual (caso o script automático não detecte corretamente)

### Passo 1 — Remover o blacklist errado e criar o correto

```bash
# Remover blacklist do ssv6051 (estava bloqueando o driver correto)
sudo rm -f /etc/modprobe.d/blacklist-ssv6051.conf

# Criar blacklist do ssv6x5x (driver incorreto para este chip)
echo "blacklist ssv6x5x" | sudo tee /etc/modprobe.d/blacklist-ssv6x5x.conf
```

### Passo 2 — Garantir carregamento automático do ssv6051 no boot

```bash
echo "ssv6051" | sudo tee /etc/modules-load.d/ssv6051.conf
```

### Passo 3 — Atualizar o initramfs e reiniciar

```bash
sudo update-initramfs -u
sudo reboot
```

### Passo 4 — Verificar após o reboot

```bash
# Módulo correto carregado
lsmod | grep ssv
# ssv6051   155648  0  ← correto

# Interface presente
ip link show wlan0
# wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...

# Calibração bem-sucedida
dmesg | grep -i "calibration"
# SSV WLAN driver ssv6200: Calibration successful
```

---

## Sobre o NetworkManager e o Modo AP

Com o chip RSV6200A, foi identificado um comportamento adicional: após o reboot, o **NetworkManager conectava o `wlan0` automaticamente a uma rede Wi-Fi local** como cliente (`type managed`), impedindo o hostapd de usar a interface como Access Point.

**Sintomas:**
- A rede do hotspot não aparece para outros dispositivos
- `iw dev wlan0 info` mostra `type managed` e `ssid <rede_local>` em vez de `type AP`
- `wlan0` em estado `DORMANT`

**Solução — impedir o NM de gerenciar o wlan0:**

```bash
sudo tee /etc/NetworkManager/conf.d/unmanaged-wlan0.conf << 'EOF'
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF

sudo systemctl restart NetworkManager
```

Esta configuração já está incluída no script `02-setup-ap.sh`.

---

## Sobre o Timing de Inicialização

O driver `ssv6051` precisa de alguns segundos para inicializar completamente o chip RSV6200A via SDIO antes que o `dnsmasq` e o `hostapd` possam usar a interface. Sem o delay correto:

- `dnsmasq` falha com `unknown interface wlan0`
- `hostapd` ativa o AP mas sem rádio funcional (`wlan0` em `DORMANT`)

**Solução — `rc.local` com delays corretos:**

```bash
#!/bin/bash
sleep 5                          # Aguarda inicialização do ssv6051
systemctl stop NetworkManager    # Impede interferência do NM
ip addr flush dev wlan0
ip addr add 192.168.50.1/24 dev wlan0
ip link set wlan0 up
sleep 2                          # Aguarda interface estabilizar
systemctl restart dnsmasq        # Reinicia APÓS wlan0 configurado
systemctl restart hostapd
exit 0
```

Esta lógica já está incluída no script `02-setup-ap.sh`.

---

## Resumo do Diagnóstico

| Hipótese | Teste | Resultado |
|---|---|---|
| Driver ausente | `lsmod \| grep ssv` | ssv6x5x carregado (errado) |
| Chip incompatível | `dmesg \| grep "chip id"` | RSV6200A — não suportado pelo ssv6x5x |
| Driver correto | `modprobe ssv6051` | Calibration successful |
| NM interferindo | `iw dev wlan0 info` | `type managed`, ssid da rede local |
| Timing de boot | `journalctl -u dnsmasq` | "unknown interface wlan0" |
| Solução final | NM unmanaged + delays no rc.local | AP funcionando após reboot |

---

## Referências

- [Fórum Armbian — CSC RK322x](https://forum.armbian.com/topic/34923-csc-armbian-for-rk322x-tv-box-boards/)
- [Driver ssv6051 no kernel Linux](https://github.com/torvalds/linux/tree/master/drivers/net/wireless)
- [hostapd documentation](https://w1.fi/hostapd/)
