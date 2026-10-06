# Pi-hole em Docker — Raspberry Pi 4

Stack de DNS da casa: **Pi-hole** (bloqueio de anúncios) com **Unbound**
(resolvedor recursivo) como upstream, em containers no Raspberry Pi 4 da rede
local
(`192.168.15.5`, IP reservado no roteador, conectado por Wi-Fi em `wlan0`).

O caminho de uma consulta: cliente → Pi-hole (filtra) → Unbound (resolve a
partir dos servidores raiz) → internet. Nenhum resolvedor de terceiros no meio.
O sistema fica num cartão SD.

Esta pasta guarda a **receita completa**: tanto o preparo do sistema
operacional (`setup-host.sh`) quanto a definição do container
(`docker-compose.yml`). O estado (senha, export Teleporter) não fica aqui:
vai no backup semanal criptografado da pasta `backup/`.

## Variáveis do `.env`

O `.env` não é versionado. Quem o escreve é o deploy, a partir dos secrets do
Environment `production` no GitHub (mapa em `deploy/env-manifest`, ver pasta
`deploy/`). Para trocar um valor, editar o secret e rodar o workflow Deploy.
Ele também vai no backup semanal (`docker/pihole/.env` dentro do `.tar.gz`).

| Variável | Conteúdo |
|---|---|
| `PIHOLE_PASSWORD` | Senha do painel web (guardada no Bitwarden) |

## Subir

```bash
docker compose up -d
```

O painel fica em `http://192.168.15.5/admin`.

## Restaurar do zero num Pi novo

1. Gravar o Raspberry Pi OS (64-bit) no cartão e criar o usuário `admin`
2. Copiar a pasta `pihole/` deste repositório para `~/docker/pihole` (ver *Restaurar o Pi do zero* no README da raiz)
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
5. Recolocar o `.env` (ver *Variáveis do `.env`*) e subir:
   ```bash
   cd ~/docker/pihole && docker compose up -d
   ```
6. Recadastrar os clientes nomeados: `./clients.sh`
7. Apontar o DNS dos clientes para o IP do Pi (ver *Quem usa o Pi-hole*)

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
- **`Storage=persistent` no journald** (aplicado pelo `setup-host.sh`) — sem
  isso o log2ram deixa o journal em `/run`, volátil, e todo o histórico some a
  cada reinício. Com a correção o journal fica no tmpfs e o log2ram copia para
  `/var/hdd.log` no desligamento e uma vez por dia. O limite de 32 MB existe
  para o journal não encher os 64 MB do tmpfs.
- **`cgroup_enable=memory` no cmdline.txt** (aplicado pelo `setup-host.sh`) — o
  Raspberry Pi OS não habilita o controlador de memória do cgroup por padrão.
  Sem ele o kernel não contabiliza memória por container: `docker stats` mostra
  zero, ferramentas de monitoramento não leem nada e limites de memória são
  ignorados em silêncio. Editar esse arquivo exige cuidado — ele precisa
  continuar com uma única linha, ou o Pi não inicia.
- **Usuário no grupo `systemd-journal`** — o log2ram não preserva as ACLs ao
  restaurar `/var/log`, então os journals antigos voltam ilegíveis. Pelo grupo,
  o acesso passa a depender só do modo `640`.
- **NTP desligado** — o host já sincroniza a hora via `systemd-timesyncd`;
  deixar o servidor NTP do Pi-hole ativo só disputaria a porta 123.
- **`FTLCONF_dns_interface: wlan0`** — o Pi está em Wi-Fi. Se migrar para cabo,
  trocar para `eth0`.

## Quem usa o Pi-hole

Por escolha, **só alguns aparelhos** passam pelo Pi-hole — o DHCP do roteador
não distribui o IP do Pi. Cada aparelho aponta o DNS manualmente para
`192.168.15.5`, sem DNS secundário (um secundário faria parte das consultas
escapar do bloqueio). Fora de casa, os peers do WireGuard já entregam o Pi-hole
como DNS.

Os aparelhos têm IP reservado no roteador e são cadastrados no Pi-hole **por
MAC** pelo `clients.sh`, que lê a lista do `clients.list` (fora do Git). A fonte
da verdade é o secret `PIHOLE_CLIENTS_LIST`: quando ele muda, o deploy
reescreve o arquivo e roda o `clients.sh`. Uma linha por aparelho, `#` para comentário:

```
AA:BB:CC:DD:EE:01|Celular   # IP reservado no roteador, só como referência
```

Para incluir um aparelho, acrescentar a linha e rodar o script de novo.

## Comandos do dia a dia

Como o Pi-hole está em container, o comando `pihole` não existe no host:

```bash
docker exec pihole pihole -g        # atualizar listas (gravity)
docker exec pihole pihole status
docker compose logs -f              # acompanhar logs
docker compose pull && docker compose up -d   # atualizar (após trocar a tag)
```

## Backup

Automático, pela pasta `backup/`: toda semana ele gera o
Teleporter, junta com o `.env` e envia criptografado para o Google Drive. Para
um export avulso: `docker exec pihole pihole-FTL --teleporter`.
