# tv-box-linux

Documentação e scripts para transformar TV boxes genéricas com SoC Rockchip RK322x, que vêm com Android, em servidores Linux com Access Point Wi-Fi e internet compartilhada por NAT. O passo a passo foi feito e testado em quatro modelos de TV box.

## O que dá trabalho

TV boxes iguais por fora trazem chips Wi-Fi diferentes por dentro, e o driver do fabricante só existe para o kernel 4.4. No kernel 6.x, o chip SSV6X5X precisa de um driver externo compilado via DKMS, enquanto o RSV6200A usa o `ssv6051`, que já vem no kernel. Instalar o driver errado faz o chip falhar sem uma mensagem clara.

O segundo problema é o NetworkManager. Em algumas unidades ele conecta o `wlan0` como cliente de uma rede local, e o hostapd não consegue colocar a interface em modo AP.

## Hardware

| Componente | Especificação |
|---|---|
| SoC | Rockchip RK3228A (família RK322x) |
| Arquitetura | ARMv7l, 32 bits (Cortex-A7) |
| RAM | cerca de 1 GB DDR3 |
| Armazenamento | eMMC (com Android de fábrica) e slot microSD |
| Ethernet | embutida no SoC, interface `end0` (driver stmmac) |
| Sistema | Armbian 26.8.0 (community), Debian 13 "Trixie" Minimal |
| Kernel | 6.18.x-current-rockchip |

## Chips Wi-Fi conhecidos

| Chip | Driver | Compilação | Neste repositório |
|---|---|---|---|
| SSV6501P / SV6256P | `ssv6x5x` (externo) | DKMS | tratado |
| RSV6200A | `ssv6051` (nativo no kernel) | não | tratado |
| Realtek RTL8723BS | `r8723bs` (nativo) mais o pacote `firmware-realtek` | não | identificado e com firmware instalado pelo script 01 |

Todos se ligam ao SoC por SDIO, então não aparecem no `lsusb`. Os dois drivers SSV não podem carregar ao mesmo tempo, por isso cada unidade precisa do blacklist do driver que não usa. O `01-install-wifi-driver.sh` identifica o chip e aplica o blacklist certo.

A identificação segue uma ordem. A Realtek se denuncia sozinha no dmesg, porque o `r8723bs` se liga ao dispositivo antes de qualquer script rodar. Para as outras duas, o `ssv6051` não ajuda: ele falha com a mesma saída nos dois chips SSV. Só o `ssv6x5x` lê o Chip ID e rejeita com erro -22 o chip que não é da família dele, então o script o compila via DKMS e o usa como sonda, mesmo nas unidades que acabam usando o `ssv6051`. O [doc 01](docs/01-identificacao-hardware.md) tem o raciocínio completo.

A variante Realtek apareceu durante o desenvolvimento do [chonOS](https://os.chon.group). Sem o `firmware-realtek` o rádio nunca recebe firmware e o AP fica no ar sem transmitir. O script 02 (Access Point) ainda não foi validado numa unidade Realtek neste repositório.

## Topologia

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

## Pré-requisitos

- TV box com SoC Rockchip RK322x (RK3228A ou RK3229)
- Cartão microSD de pelo menos 8 GB, para a instalação inicial
- Cabo Ethernet ligado à TV box
- Acesso SSH à TV box depois do primeiro boot

## Passo a passo

### 1. Instalar o Armbian

Baixe o Armbian Imager em [imager.armbian.com](https://imager.armbian.com), escolha `rk322x-box` e Debian 13 Minimal, e grave no microSD com o Autoconfig Profile preenchido (usuário, senha, Wi-Fi e fuso horário).

### 2. Clonar o repositório na TV box

```bash
git clone https://github.com/caioamorimr/tv-box-linux.git
cd tv-box-linux
```

### 3. Instalar o driver Wi-Fi

```bash
sudo bash scripts/01-install-wifi-driver.sh
sudo reboot
```

O script identifica o chip e instala o driver correspondente. A primeira execução leva alguns minutos, porque a sondagem compila o `ssv6x5x` mesmo quando o chip acaba sendo outro. Se o `apt upgrade` trouxer um kernel novo, ele pede um reboot antes de compilar qualquer coisa, e você roda o script de novo depois. Para conferir:

```bash
ip link show wlan0
# esperado: state UP
```

### 4. Configurar o Access Point

Edite as variáveis no topo do script (`SSID`, `PASSPHRASE`, `CHANNEL`, `AP_IP`, `WAN_IFACE`) e execute:

```bash
nano scripts/02-setup-ap.sh
sudo bash scripts/02-setup-ap.sh
```

### 5. Instalar na eMMC (permanente)

```bash
sudo armbian-config
# System → Storage → TO001 (Copy running system)
# escolha eMMC → Boot from eMMC → ext4
# desligue, remova o microSD e ligue de novo
```

## Estrutura do repositório

```
tv-box-linux/
├── docs/
│   ├── 01-identificacao-hardware.md
│   ├── 02-instalacao-armbian.md
│   ├── 03-driver-wifi-ssv6x5x.md
│   ├── 03b-driver-wifi-rsv6200a.md
│   └── 04-access-point.md
├── configs/
│   ├── hostapd.conf
│   ├── dnsmasq.conf
│   ├── blacklist-ssv6051.conf     bloqueio do ssv6051 nas unidades SSV6X5X
│   ├── ssv6x5x.conf               caminhos do firmware do driver
│   ├── ssv6x5x-wifi.cfg           configuração do chip
│   ├── 99-ip-forward.conf         IP forwarding persistente (sysctl.d)
│   ├── sysctl.conf
│   └── rc.local                   IP fixo e ordem de inicialização dos serviços
└── scripts/
    ├── 01-install-wifi-driver.sh
    └── 02-setup-ap.sh
```

O bloqueio do `ssv6x5x`, usado nas unidades RSV6200A, não fica em `configs/`: o próprio script 01 gera `/etc/modprobe.d/blacklist-ssv6x5x.conf` quando precisa.

## Documentação

| Arquivo | Conteúdo |
|---|---|
| [01 Identificação do hardware](docs/01-identificacao-hardware.md) | SoC, chips Wi-Fi e como distingui-los |
| [02 Instalação do Armbian](docs/02-instalacao-armbian.md) | escolha da imagem, gravação, Autoconfig Profile e primeiro boot |
| [03 Driver SSV6X5X](docs/03-driver-wifi-ssv6x5x.md) | chip SSV6501P/SV6256P: DKMS e blacklist do `ssv6051` |
| [03b Driver RSV6200A](docs/03b-driver-wifi-rsv6200a.md) | chip RSV6200A: driver nativo `ssv6051` e blacklist do `ssv6x5x` |
| [04 Access Point](docs/04-access-point.md) | hostapd, dnsmasq, NAT, `ip_forward`, NetworkManager e timing de boot |

## O que foi validado

Nas unidades com SSV6X5X e RSV6200A, o `wlan0` sobe depois do boot, o AP WPA2 fica no ar, os clientes recebem IP por DHCP e a internet chega por NAT. O `ip_forward` persiste entre boots e o NetworkManager deixa de tomar o `wlan0`.

## Problemas conhecidos

### `wlan0` em estado DOWN depois do boot

Causa: um módulo conflitante (`ssv6051` ou `ssv6x5x`) carrega antes do driver certo e corrompe o estado do chip no barramento SDIO.

Diagnóstico:

```bash
dmesg | grep -i "chip id"     # identificar o chip
lsmod | grep ssv              # ver qual módulo está carregado
```

Solução: aplicar o blacklist correto para o chip presente e atualizar o initramfs. O script 01 faz os dois.

### A rede do hotspot não aparece

Causa mais comum: o NetworkManager conectou o `wlan0` como cliente de uma rede Wi-Fi local, e o hostapd não opera em modo AP.

Diagnóstico:

```bash
iw dev wlan0 info
# "type managed" e "ssid <nome_da_rede>" indicam que o NM tomou a interface
```

Solução:

```bash
sudo tee /etc/NetworkManager/conf.d/unmanaged-wlan0.conf << 'EOT'
[keyfile]
unmanaged-devices=interface-name:wlan0
EOT
sudo systemctl restart NetworkManager
sudo systemctl restart hostapd
```

### dnsmasq falha com "unknown interface wlan0"

Causa: o dnsmasq iniciou antes de o `wlan0` receber IP, um problema de timing no boot.

Solução: o `rc.local` precisa reiniciar o dnsmasq depois de configurar o IP do `wlan0`. O script `02-setup-ap.sh` já faz isso.

### `ip_forward` volta a 0 depois do reboot

Causa: o Armbian processa o `/etc/sysctl.conf` tarde demais no boot.

Solução:

```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

### Erro de headers no DKMS: "cannot be found at /lib/modules/.../build"

Causa: a versão do kernel em execução é diferente da dos headers instalados.

Solução:

```bash
sudo apt update && sudo apt upgrade -y
sudo reboot
# rode o script 01 de novo depois do reboot
```

## Referências

- [Armbian rk322x-box](https://www.armbian.com/rk322x-box/)
- [Fórum Armbian: CSC Armbian for RK322x TV box boards](https://forum.armbian.com/topic/34923-csc-armbian-for-rk322x-tv-box-boards/)
- [Driver SSV6X5X para kernel 6.x (cdhigh/armbian_sv6256p)](https://github.com/cdhigh/armbian_sv6256p)
- [Driver SSV6X5X original para RK322x (paolosabatino/ssv6x5x)](https://github.com/paolosabatino/ssv6x5x)
- [Fórum Armbian: SV6256P WiFi working on Linux 6.x](https://forum.armbian.com/topic/57960-sv6256p-wifi-now-working-on-linux-6x-armbian-tested/)
- [hostapd](https://w1.fi/hostapd/)
- [dnsmasq](https://thekelleys.org.uk/dnsmasq/doc.html)