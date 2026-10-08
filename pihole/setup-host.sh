#!/usr/bin/env bash
# Prepara um Raspberry Pi recem-instalado para rodar o Pi-hole em container.
# Idempotente: rodar de novo nao quebra nada, so pula o que ja existe.
set -euo pipefail

LOG2RAM_SIZE="64M"

echo "==> Atualizando o sistema"
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

if command -v docker >/dev/null 2>&1; then
  echo "==> Docker ja instalado, pulando"
else
  echo "==> Instalando Docker"
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  echo "    Relogue (ou reinicie) para usar docker sem sudo."
fi

# log2ram mantem /var/log em RAM e grava no disco so periodicamente,
# poupando ciclos de escrita do cartao SD.
if dpkg -s log2ram >/dev/null 2>&1; then
  echo "==> log2ram ja instalado, pulando"
else
  echo "==> Instalando log2ram"
  sudo wget -q -O /usr/share/keyrings/azlux-archive-keyring.gpg https://azlux.fr/repo.gpg
  echo "deb [signed-by=/usr/share/keyrings/azlux-archive-keyring.gpg] http://packages.azlux.fr/debian/ stable main" \
    | sudo tee /etc/apt/sources.list.d/azlux.list >/dev/null
  sudo apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq log2ram
  sudo sed -i "s/^SIZE=.*/SIZE=${LOG2RAM_SIZE}/" /etc/log2ram.conf
  echo "    log2ram configurado com ${LOG2RAM_SIZE} (ativa apos reboot)."
fi

# O journald usa Storage=auto, que so grava em disco se /var/log/journal existir
# quando ele sobe. Como o log2ram monta /var/log como tmpfs durante o boot, o
# journald perde a corrida e cai para /run (volatil) — e o historico some a cada
# reinicio. Forcar persistent resolve sem abrir mao do log2ram: o journal fica
# em RAM e o log2ram sincroniza para /var/hdd.log.
echo "==> Garantindo journal persistente entre reinicios"
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/99-persistent.conf >/dev/null <<'CONF'
[Journal]
Storage=persistent
# Teto abaixo do tmpfs do log2ram, senao o journal enche /var/log.
SystemMaxUse=32M
CONF
sudo mkdir -p /var/log/journal
[ -d /var/hdd.log ] && sudo mkdir -p /var/hdd.log/journal
sudo systemctl restart systemd-journald

# O log2ram copia /var/log para disco sem preservar as ACLs que o journald usa
# para liberar leitura ao grupo adm. Sem isso, os journals restaurados ficam
# ilegiveis para o usuario e o historico "some" mesmo estando no disco.
# Entrar no grupo systemd-journal da acesso pelo modo 640, sem depender de ACL.
if id -nG "$USER" | grep -qw systemd-journal; then
  echo "==> Usuario ja le o journal, pulando"
else
  echo "==> Dando acesso de leitura ao journal"
  sudo usermod -aG systemd-journal "$USER"
  echo "    Relogue para o grupo valer."
fi

# O Raspberry Pi OS nao habilita o controlador de memoria do cgroup por padrao.
# Sem ele o kernel nao contabiliza memoria por container: docker stats mostra
# zero, ferramentas de monitoramento nao leem nada e limites de memoria sao
# silenciosamente ignorados.
CMDLINE=/boot/firmware/cmdline.txt
if [ ! -f "$CMDLINE" ]; then
  echo "==> $CMDLINE nao encontrado, pulando cgroup de memoria"
elif grep -q 'cgroup_enable=memory' "$CMDLINE"; then
  echo "==> cgroup de memoria ja habilitado, pulando"
else
  echo "==> Habilitando cgroup de memoria"
  sudo cp "$CMDLINE" "$CMDLINE.bak"
  # O arquivo precisa continuar com UMA linha: uma quebra aqui impede o boot.
  sudo sed -i '1 s/$/ cgroup_enable=memory cgroup_memory=1/' "$CMDLINE"
  echo "    Aplicado (ativa apos reboot). Backup em $CMDLINE.bak"
fi

# O 5 GHz do roteador usa canal DFS, que o firmware da operadora nao deixa
# trocar. Ao detectar radar o roteador cala esse canal, e o Pi fica associado
# sem trafego ate o lease do DHCP vencer (~2 h fora do ar). Em 2,4 GHz isso nao
# acontece, e para DNS a velocidade nao faz diferenca. O network-config e a
# fonte da verdade: o cloud-init regenera a rede a partir dele a cada boot.
NETCFG=/boot/firmware/network-config
if [ ! -f "$NETCFG" ]; then
  echo "==> $NETCFG nao encontrado, pulando Wi-Fi em 2,4 GHz"
elif grep -qE '^\s*band:' "$NETCFG"; then
  echo "==> Wi-Fi ja fixado em uma banda, pulando"
else
  echo "==> Fixando o Wi-Fi em 2,4 GHz"
  sudo cp -p "$NETCFG" "$NETCFG.bak"
  sudo sed -i 's/^\(\s*\)password: \(.*\)$/\1password: \2\n\1band: "2.4GHz"/' "$NETCFG"
  if ! cloud-init schema -t network-config -c "$NETCFG" 2>/dev/null | grep -q '^Valid'; then
    sudo cp -p "$NETCFG.bak" "$NETCFG"
    echo "    network-config ficou invalido; backup restaurado, nada aplicado."
  else
    # Grava tambem na conexao ativa, sem reconectar: a sessao SSH passa pelo
    # proprio Wi-Fi. Vale a partir da proxima conexao ou do reboot.
    WIFI_CON=$(nmcli -g NAME,DEVICE connection show --active | grep ':wlan0$' | cut -d: -f1 || true)
    [ -n "$WIFI_CON" ] && sudo nmcli connection modify "$WIFI_CON" 802-11-wireless.band bg
    echo "    Aplicado (ativa apos reboot). Backup em $NETCFG.bak"
  fi
fi

# Agendamentos do usuario. Os scripts chegam com o deploy; enquanto o .env de
# cada servico nao for restaurado, eles apenas falham sem efeito. A linha do
# backup e instalada pelo backup/configure.sh.
CRON_LINES=(
  "*/5 * * * * /home/admin/docker/beszel/healthcheck-ping.sh"
  "*/5 * * * * /home/admin/docker/wireguard/ddns-check.sh 2>&1 | systemd-cat -t ddns-check"
)
for line in "${CRON_LINES[@]}"; do
  script=$(awk '{print $6}' <<<"$line")
  if crontab -l 2>/dev/null | grep -qF "$script"; then
    echo "==> Cron de $(basename "$script") ja existe, pulando"
  else
    echo "==> Agendando $(basename "$script") a cada 5 min"
    (crontab -l 2>/dev/null || true; echo "$line") | crontab -
  fi
done

echo
echo "Sistema pronto. Reinicie para ativar o log2ram e depois suba o Pi-hole:"
echo "  cd ~/docker/pihole   # recoloque o .env (do backup ou com PIHOLE_PASSWORD=...)"
echo "  docker compose up -d"
