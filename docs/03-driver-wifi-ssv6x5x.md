# 03 — Driver Wi-Fi SSV6X5X no Debian/Armbian (RK322x)

## Visão Geral

Esta foi a etapa mais complexa do projeto. O chip Wi-Fi SSV6501P (família SSV6X5X) **não possui driver nativo no kernel Linux mainline** e o driver original do fabricante só compila contra o kernel 4.4 legado da Rockchip. Kernels modernos (5.x, 6.x) exigem um port comunitário compilado manualmente.

---

## Ambiente

| Item | Valor |
|---|---|
| Hardware | TV Box RK3228A (RK322x) |
| Chip Wi-Fi | SSV6501P / SV6256P (família SSV6X5X, barramento SDIO) |
| Sistema | Armbian 26.8.0 — Debian 13 Trixie |
| Kernel | 6.18.36-current-rockchip |
| Arquitetura | ARMv7l (32-bit) |
| Driver utilizado | [github.com/cdhigh/armbian_sv6256p](https://github.com/cdhigh/armbian_sv6256p) |
| Método de instalação | DKMS (recompilação automática em updates de kernel) |

---

## O Problema

Após o primeiro boot com o Armbian, a interface `wlan0` estava presente mas com estado `DOWN` e impossível de ativar:

```bash
ip link set wlan0 up
# RTNETLINK answers: Operation not permitted
```

Os logs do kernel revelaram a causa raiz:

```bash
dmesg | grep -iE "ssv|wlan|calibr"
```

```
ssv6051: probe of ssv6051 failed with error -12
SSV WLAN driver ssv6200: calibration fail after 10 iterations
```

### Causa Raiz: Conflito de Módulos no Barramento SDIO

O Armbian inclui no kernel um módulo chamado `ssv6051` — um driver genérico para chips da família SSV6200 de geração anterior. Esse módulo **carregava automaticamente no boot** e tentava inicializar o chip pelo barramento SDIO antes do driver correto (`ssv6x5x`) ter chance de fazê-lo.

O resultado era um conflito no barramento SDIO: o `ssv6051` falhava na calibração de RF do chip, deixava o hardware em estado inconsistente, e o driver correto (`ssv6x5x`) também falhava ao tentar inicializar depois.

```
ssv6051 carrega → tenta calibrar → falha → chip fica em estado inválido
ssv6x5x carrega → tenta inicializar chip já corrompido → falha
wlan0 → state DOWN, impossível ativar
```

---

## Solução em 4 Etapas

### Etapa 1 — Instalar Dependências de Compilação

```bash
sudo apt update
sudo apt install -y build-essential git dkms linux-headers-current-rockchip
```

> **Atenção (específico do Armbian):** O pacote de headers no Armbian **não inclui a versão no nome**. O comando correto é `linux-headers-current-rockchip`, não `linux-headers-6.18.36-current-rockchip`. Este foi um ponto de confusão durante o projeto.

Confirme que os headers estão no lugar certo:

```bash
ls /lib/modules/$(uname -r)/build
# Deve listar os arquivos de build do kernel
```

### Etapa 2 — Clonar e Instalar via DKMS

O repositório já inclui um script `install-dkms.sh` que automatiza todo o processo: copia os fontes para o diretório do DKMS, gera o `dkms.conf` com os parâmetros corretos para ARMv7l (`ARCH=arm`) e executa o build e a instalação.

```bash
# Clonar o repositório
git clone https://github.com/cdhigh/armbian_sv6256p.git
cd armbian_sv6256p

# Instalar via DKMS (já inclui compilação e registro do módulo)
sudo bash ./install-dkms.sh

# Carregar o módulo imediatamente sem precisar reiniciar
sudo modprobe ssv6x5x
```

> **Por que `ARCH=arm` internamente?** O script `install-dkms.sh` já configura `ARCH=arm` automaticamente para ARMv7l. Não é necessário passar o parâmetro manualmente. O README do repositório usa `arm64` como exemplo porque foi testado originalmente em SoCs AArch64 (64-bit) — no RK3228A (32-bit) o script cuida disso.

O DKMS (Dynamic Kernel Module Support) recompila o módulo automaticamente sempre que o kernel for atualizado, eliminando a necessidade de recompilar manualmente no futuro.

Verifique a instalação:

```bash
dkms status
# ssv6x5x/1.0, 6.18.36-current-rockchip, armv7l: installed
```

### Etapa 3 — Instalar Firmware e Fazer Blacklist do Módulo Conflitante

```bash
# Copiar os arquivos de firmware para o local padrão
sudo cp ~/armbian_sv6256p/ssv6x5x-wifi.cfg /lib/firmware/
sudo cp ~/armbian_sv6256p/ssv6x5x-sw.bin /lib/firmware/

# Configurar os paths do firmware no modprobe
echo 'options ssv6x5x stacfgpath="/lib/firmware/ssv6x5x-wifi.cfg" cfgfirmwarepath="/lib/firmware/ssv6x5x-sw.bin"' \
  | sudo tee /etc/modprobe.d/ssv6x5x.conf

# Fazer blacklist do módulo conflitante ssv6051
echo "blacklist ssv6051" | sudo tee /etc/modprobe.d/blacklist-ssv6051.conf
echo "blacklist ssv6200" | sudo tee -a /etc/modprobe.d/blacklist-ssv6051.conf

# Atualizar o initramfs para que o blacklist persista no boot
sudo update-initramfs -u
```

Reiniciar:

```bash
sudo reboot
```

---

## Verificação Pós-instalação

```bash
# Confirmar que apenas o módulo correto está carregado
lsmod | grep ssv
# ssv6x5x   512000  0   ← correto
# ssv6051 NÃO deve aparecer

# Verificar estado da interface
ip link show wlan0
# wlan0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...  ← UP

# Ver se o chip foi inicializado corretamente
dmesg | grep -i ssv | tail -10
# Não deve conter "calibration fail"

# Confirmar modos suportados pelo chip
sudo iw phy | grep -A 10 "Supported interface modes"
# * managed
# * AP
# * AP/VLAN
# * monitor
```

---

## Conectar à Rede Wi-Fi (como cliente)

Com o driver funcionando, conectar a uma rede é simples via NetworkManager:

```bash
# Interface de texto para configuração de rede
sudo nmtui
# Selecione: "Activate a connection" → escolha a rede → insira a senha
```

Ou via linha de comando:

```bash
sudo nmcli device wifi connect "NomeDaRede" password "SenhaDaRede"
```

Verificar conectividade:

```bash
ip addr show wlan0    # confirmar IP atribuído
ping -c 4 8.8.8.8    # testar internet
```

---

## Resumo do Processo de Diagnóstico

| Hipótese | Teste | Resultado |
|---|---|---|
| rfkill bloqueando | `cat /sys/class/rfkill/*/soft` | `0` — descartado |
| Driver ausente | `lsmod \| grep ssv` | ssv6051 carregava, ssv6x5x ausente |
| Conflito de módulos | `dmesg \| grep ssv` | "calibration fail" — confirmado |
| Driver correto | Compilar ssv6x5x com ARCH=arm | Resolvido |
| Persistência | Blacklist + update-initramfs + reboot | Confirmado permanente |

---

## Referências

- [Driver SSV6X5X portado para kernel 6.x — cdhigh/armbian_sv6256p](https://github.com/cdhigh/armbian_sv6256p)
- [Driver original RK322x — paolosabatino/ssv6x5x](https://github.com/paolosabatino/ssv6x5x)
- [Fórum Armbian — SV6256P WiFi Now Working on Linux 6.x](https://forum.armbian.com/topic/57960-sv6256p-wifi-now-working-on-linux-6x-armbian-tested/)
- [LibreELEC Forum — SSV6x5x driver discussion](https://forum.libreelec.tv/thread/29001-libreelec-rk322x-arm-11-0-nightly-20240218-d7324fb-rk322x-driver-wifi-ssv6x5x-sv/)
