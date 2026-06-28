# 02 — Instalação do Armbian

## Visão Geral

Com o hardware identificado, o próximo passo é preparar e instalar o sistema operacional. Para TV Boxes baseadas no RK322x, o **Armbian** é a distribuição mais adequada: mantém suporte ativo à plataforma Rockchip, oferece kernels recentes e possui ferramentas específicas para este tipo de hardware.

O sistema é instalado em um **cartão microSD** e a TV box é configurada para bootar a partir dele, mantendo o Android intacto na memória interna (eMMC).

---

## Pré-requisitos

- Cartão microSD de pelo menos **8 GB** (recomendado 16 GB)
- PC com Linux, macOS ou Windows para gravar a imagem
- **Armbian Imager 2.0.2** (ou posterior) — disponível em [imager.armbian.com](https://imager.armbian.com) como AppImage para Linux
- Acesso à internet no PC durante a gravação

---

## Escolha da Imagem

Na página do Armbian Imager, selecione:

| Campo | Valor |
|---|---|
| Board | `rk322x-box` |
| Branch | Current |
| Release | Debian 13 "Trixie" — Minimal |

> **Por que Minimal?** A versão Minimal sem interface gráfica consome muito menos RAM e armazenamento, sendo mais adequada para um servidor/roteador embedded. A TV box tem apenas ~1 GB de RAM.

> **Por que Debian 13 e não Ubuntu?** Maior estabilidade a longo prazo para servidores embedded. O Ubuntu traz dependências extras desnecessárias para este caso de uso.

---

## Gravação com Armbian Imager

### Passo 1 — Abrir o Armbian Imager

No Linux:

```bash
chmod +x armbian-imager-2.0.2-linux-x86_64.AppImage
./armbian-imager-2.0.2-linux-x86_64.AppImage
```

### Passo 2 — Selecionar o dispositivo de destino

Insira o cartão microSD e selecione-o no Imager.

### Passo 3 — Configurar o Autoconfig Profile

O Armbian Imager permite pré-configurar o sistema antes de gravar, eliminando a necessidade de monitor e teclado na TV box. Clique em **"Customize"** ou **"Autoconfig Profile"** e preencha:

- **Usuário:** nome do usuário desejado
- **Senha:** senha do usuário e do root
- **Wi-Fi SSID:** nome da rede Wi-Fi do local
- **Wi-Fi Password:** senha da rede Wi-Fi
- **Timezone:** `America/Sao_Paulo`
- **IP:** DHCP (deixar dinâmico — mais seguro quando não há monitor)

### Passo 4 — Gravar

Clique em **"Write"** e aguarde a conclusão.

**Como confirmar que a gravação foi concluída sem a interface:**

```bash
# Verificar se o processo ainda está rodando
ps aux | grep -i imager

# Monitorar atividade de escrita no disco
watch -n 1 'cat /proc/diskstats | grep mmcblk0'

# Verificar se o cartão foi ejetado/desmontado (sinal de conclusão)
lsblk
```

Quando a atividade de escrita cessar e o processo encerrar, a gravação está completa.

---

## Primeiro Boot

### Passo 1 — Inserir o cartão e ligar

Insira o cartão microSD na TV box com o sistema **desligado**. Ligue o dispositivo. O Armbian detecta automaticamente o cartão SD e prioriza o boot por ele, deixando o Android na eMMC intocado.

> **Importante:** O cartão SD deve **permanecer inserido** durante todo o uso do sistema Linux. Se removido com o sistema ligado, o sistema trava. Para desligar corretamente:
> ```bash
> sync && sudo shutdown -h now
> ```

### Passo 2 — Aguardar o first-boot

O primeiro boot demora mais que o normal (~2-3 minutos) porque o Armbian executa rotinas de inicialização: resize do sistema de arquivos, geração de chaves SSH, aplicação do Autoconfig Profile. Aguarde até o sistema estabilizar.

### Passo 3 — Acessar via SSH

Com o Autoconfig Profile configurado, o sistema tentará conectar à rede Wi-Fi automaticamente. Descubra o IP atribuído pelo roteador e acesse:

```bash
ssh root@<IP_DA_TVBOX>
# ou com o usuário configurado:
ssh seuusuario@<IP_DA_TVBOX>
```

Na primeira conexão, confirme a chave SSH digitando `yes`.

---

## Verificação Pós-instalação

```bash
# Sistema operacional
cat /etc/os-release
# PRETTY_NAME="Armbian_community 26.8.0-trunk.170 trixie"

# Kernel
uname -r
# 6.18.36-current-rockchip

# Arquitetura
uname -m
# armv7l

# Interfaces de rede disponíveis
ip link show

# Espaço em disco
df -h /

# Memória
free -h
```

---

## Sobre o Armazenamento Interno (eMMC)

O Android de fábrica permanece intacto na eMMC durante todo este projeto. O Linux roda exclusivamente do cartão SD.

Caso queira instalar o Linux permanentemente na eMMC (substituindo o Android):

```bash
sudo armbian-config
# Menu: System → Install → Install to internal storage
```

> ⚠️ **Este processo é irreversível** — o Android é apagado permanentemente. Recomendado apenas após todo o projeto estar documentado e validado.

---

## Referências

- [Armbian Imager](https://imager.armbian.com)
- [Armbian — rk322x-box](https://www.armbian.com/rk322x-box/)
- [Fórum Armbian — CSC Armbian for RK322x](https://forum.armbian.com/topic/34923-csc-armbian-for-rk322x-tv-box-boards/)
