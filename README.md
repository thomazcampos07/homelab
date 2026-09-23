# Pi-hole em Docker — Raspberry Pi 4

Stack de DNS da casa: **Pi-hole** (bloqueio de anúncios) com **Unbound**
(resolvedor recursivo) como upstream, em containers no Raspberry Pi 4 da rede
local
(`192.168.15.5`, IP reservado no roteador, conectado por Wi-Fi em `wlan0`).

O caminho de uma consulta: cliente → Pi-hole (filtra) → Unbound (resolve a
partir dos servidores raiz) → internet. Nenhum resolvedor de terceiros no meio.
O sistema fica num cartão SD.

Este repositório guarda a **receita completa**: tanto o preparo do sistema
operacional (`setup-host.sh`) quanto a definição do container
(`docker-compose.yml`). Os backups do Pi-hole ficam em `backups/`, que não é
versionado — o export Teleporter contém chave privada TLS e o hash da senha da
API.

## Subir

```bash
cp .env.example .env     # defina uma senha forte
chmod 600 .env
docker compose up -d
```

O painel fica em `http://192.168.15.5/admin`.

## Restaurar do zero num Pi novo

1. Gravar o Raspberry Pi OS (64-bit) no cartão e criar o usuário `admin`
2. Copiar este repositório para `~/docker/pihole` (via `git clone` ou `scp`)
3. Preparar o sistema — instala Docker e log2ram:
   ```bash
   ./setup-host.sh
   sudo reboot
   ```
4. Gerar o trust anchor do DNSSEC (não é versionado, cada instalação gera o seu):
   ```bash
   mkdir -p unbound/keys
   docker run --rm -v "$PWD/unbound/keys:/keys"      --entrypoint unbound-anchor klutchell/unbound:v1.26.1 -a /keys/root.key
   ```
   Sai com código 1 quando cria a chave — é o comportamento normal.
5. Criar o `.env` com a senha do painel e subir:
   ```bash
   cd ~/docker/pihole && cp .env.example .env
   docker compose up -d
   ```
6. Apontar o DNS dos clientes (ou o DHCP do roteador) para o IP do Pi

A lista de bloqueio é reconstruída sozinha a partir da adlist padrão — não é
preciso restaurar backup. Se houver um Teleporter com customizações a recuperar,
importar pelo painel em *Settings → Teleporter*.

Reinstalar o sistema gera **novas chaves de host SSH**, então o cliente vai
reclamar de identidade alterada. Corrigir com `ssh-keygen -R <ip>` e reautorizar
a chave pública em `~/.ssh/authorized_keys`.

## Decisões de configuração

- **`network_mode: host`** — necessário para o Pi-hole enxergar o IP real de cada
  cliente. Com `bridge`, toda query chegaria como vinda de `172.17.0.1` e os
  relatórios por dispositivo ficariam inúteis.
- **Tag de imagem pinada** — nunca `:latest`. Atualizar é trocar a tag, e o
  rollback é voltar para a anterior.
- **Retenção de 30 dias** (`maxDBdays`, padrão é 91) — cartão SD tolera menos
  ciclos de escrita, e o banco de queries grava continuamente.
- **log2ram com 64 MB** — mantém `/var/log` em RAM e sincroniza com o disco
  periodicamente. Cobre o journald, mas **não** cobre o banco do Pi-hole nem os
  logs do Docker, que ficam fora de `/var/log`.
- **Unbound como upstream** (`127.0.0.1#5335`) — resolve recursivamente a partir
  dos servidores raiz em vez de perguntar à Cloudflare, então nenhum terceiro vê
  o histórico de navegação da casa. Valida DNSSEC: responde SERVFAIL a
  assinaturas adulteradas em vez de repassá-las.
- **Unbound publicado só em `127.0.0.1:5335`** — um resolvedor recursivo aberto
  à rede pode ser abusado em ataques de amplificação. A porta 5335 é a convenção
  do Pi-hole; 5353 não serve porque o avahi já a ocupa.
- **`do-daemonize: no` no unbound.conf** — a imagem é distroless e chama o
  binário direto. Sem isso o unbound faz fork, o processo principal termina e o
  container morre em loop com exit 0.
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
