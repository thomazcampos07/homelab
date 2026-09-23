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

echo
echo "Sistema pronto. Reinicie para ativar o log2ram e depois suba o Pi-hole:"
echo "  cd ~/docker/pihole && cp .env.example .env   # defina a senha do painel"
echo "  docker compose up -d"
