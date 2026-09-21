# Pi-hole em Docker — Raspberry Pi 4

Configuração do Pi-hole rodando em container no Raspberry Pi 4 da rede local
(`192.168.15.5`, IP reservado no roteador, conectado por Wi-Fi em `wlan0`).

Este repositório guarda a **receita**. Os backups do Pi-hole ficam em `backups/`,
que não é versionado — o export Teleporter contém chave privada TLS e o hash da
senha da API.

## Subir

```bash
cp .env.example .env     # defina uma senha forte
chmod 600 .env
docker compose up -d
```

O painel fica em `http://192.168.15.5/admin`.

## Restaurar do zero num Pi novo

1. Instalar o Docker: `curl -fsSL https://get.docker.com | sh`
2. Adicionar o usuário ao grupo: `sudo usermod -aG docker $USER` (exige relogar)
3. Clonar este repositório em `~/docker/pihole`
4. Criar o `.env` com a senha do painel
5. `docker compose up -d`
6. Apontar o DNS dos clientes (ou o DHCP do roteador) para o IP do Pi

A lista de bloqueio é reconstruída sozinha a partir da adlist padrão — não é
preciso restaurar backup. Se houver um Teleporter com customizações a recuperar,
importar pelo painel em *Settings → Teleporter*.

## Decisões de configuração

- **`network_mode: host`** — necessário para o Pi-hole enxergar o IP real de cada
  cliente. Com `bridge`, toda query chegaria como vinda de `172.17.0.1` e os
  relatórios por dispositivo ficariam inúteis.
- **Tag de imagem pinada** — nunca `:latest`. Atualizar é trocar a tag, e o
  rollback é voltar para a anterior.
- **NTP desligado** — o host já sincroniza a hora via `systemd-timesyncd`;
  deixar o servidor NTP do Pi-hole ativo só disputaria a porta 123.
- **`FTLCONF_dns_interface: wlan0`** — o Pi está em Wi-Fi. Se migrar para cabo,
  trocar para `eth0`.

## Comandos do dia a dia

Como o Pi-hole está em container, o comando `pihole` não existe no host:

```bash
docker exec pihole pihole -g        # atualizar listas (gravity)
docker exec pihole pihole status
docker compose logs -f              # acompanhar logs
docker compose pull && docker compose up -d   # atualizar (após trocar a tag)
```

## Backup

```bash
docker exec pihole pihole-FTL --teleporter
```

Gera um `.zip` dentro do container; copiar para `backups/` com `docker cp`.
