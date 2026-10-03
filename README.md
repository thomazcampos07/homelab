# Homelab — Raspberry Pi 4

Receitas de tudo que roda no Raspberry Pi 4 da casa, em containers.

- **IP:** `192.168.15.5` (reservado no roteador, gateway `192.168.15.1`), Wi-Fi em `wlan0`
- **Acesso:** `ssh admin@192.168.15.5`
- **Hardware:** 1 GB de RAM, cartão SD de 64 GB, Debian Trixie arm64, sem RTC

## O que tem aqui

Cada pasta espelha uma pasta de `~/docker/` no Pi e tem seu próprio README.

| Pasta | O que é | Acesso |
|---|---|---|
| [`pihole/`](pihole/) | DNS da casa: Pi-hole + Unbound. Também tem o `setup-host.sh`, que prepara o sistema | painel em `http://192.168.15.5/admin` |
| [`wireguard/`](wireguard/) | VPN com DuckDNS, que leva o Pi-hole para fora de casa | `UDP 51820` |
| [`beszel/`](beszel/) | Monitoramento (hub + agente) e o `healthcheck-ping.sh` (alerta de Pi desligado) | painel em `http://192.168.15.5:8090` |
| [`backup/`](backup/) | Backup semanal criptografado para o Google Drive, com rclone | — |

O que **não** está no Git (`.env`, chaves do WireGuard, dados do Beszel,
Teleporter do Pi-hole, crontab) vai no backup semanal da pasta `backup/`.

## Levar uma mudança para o Pi

O Pi não tem clone deste repositório: os arquivos são copiados. Envie a versão
**commitada** (que é LF), não o arquivo do working tree do Windows (que pode
estar em CRLF). No Git Bash:

```bash
git show HEAD:pihole/docker-compose.yml | ssh admin@192.168.15.5 'cat > ~/docker/pihole/docker-compose.yml'
ssh admin@192.168.15.5 'cd ~/docker/pihole && docker compose up -d'
```

Para conferir se o Pi está igual ao Git, compare o `sha256sum` do `git show`
com o do arquivo no Pi.

## Restaurar o Pi do zero

1. Gravar o Raspberry Pi OS (64-bit) no cartão, com o usuário `admin`
2. Copiar todas as pastas para `~/docker/` (no Git Bash, a partir da raiz deste repositório):
   ```bash
   git archive HEAD pihole wireguard beszel backup | ssh admin@192.168.15.5 'mkdir -p ~/docker && tar -x -C ~/docker'
   ```
3. Preparar o sistema: `~/docker/pihole/setup-host.sh` e `sudo reboot`
4. Trazer o estado de volta do Google Drive (`.env`, chaves, dados, crontab): ver [`backup/`](backup/)
5. Subir cada serviço conforme o README da pasta. Comece pelo [`pihole/`](pihole/), que tem
   o passo do trust anchor do DNSSEC

## Atualizações de imagem

O Dependabot (`.github/dependabot.yml`) abre PR aos sábados quando sai versão
nova de alguma imagem pinada nos composes. O merge **não** faz deploy: depois
de aceitar, leve o compose ao Pi e rode `docker compose pull && docker compose up -d`.

## Histórico

Este repositório juntou, em 2026-10-03, quatro repositórios separados
(`pihole-docker`, `wireguard-docker`, `beszel-docker` e `backup-docker`), hoje
arquivados no GitHub. O histórico de commits de cada um foi preservado
(`git subtree`): os commits anteriores à junção aparecem no `git log` com os
caminhos originais, sem o prefixo da pasta, e entram pelo merge
"Traz <repo> com histórico".
