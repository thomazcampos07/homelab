# Beszel — monitoramento do Raspberry Pi 4

Monitoramento de CPU, memória, disco, rede, temperatura e containers do
Raspberry Pi 4 (`192.168.15.5`), com histórico e alertas.

Painel em **http://192.168.15.5:8090**.

São dois componentes: o **hub** (interface web e banco de histórico) e o
**agente** (coleta as métricas da máquina). Ambos rodam no mesmo Pi, mas o hub
pode monitorar outras máquinas depois — basta rodar mais agentes.

## Variáveis do `.env`

O `.env` não é versionado. Num Pi reinstalado, ele volta do backup semanal
(`docker/beszel/.env` dentro do `.tar.gz`, ver repositório `backup-docker`);
sem backup, criar à mão com as variáveis abaixo e `chmod 600 .env`.

| Variável | Conteúdo |
|---|---|
| `BESZEL_KEY` | Chave pública do hub (ver abaixo como obter) |
| `HC_PING_URL` | URL de ping do check do Pi no Healthchecks.io |

## Subir

```bash
docker compose up -d beszel          # sobe só o hub primeiro
```

A chave pública do hub é gerada no primeiro start. Para obtê-la:

```bash
docker cp beszel:/beszel_data/id_ed25519 /tmp/k && chmod 600 /tmp/k
ssh-keygen -y -f /tmp/k && rm /tmp/k
```

Coloque o resultado em `BESZEL_KEY` no `.env` e então suba o agente:

```bash
docker compose up -d
```

No painel, em **Add System**, use host `192.168.15.5` e porta `45876`.

## Dependência importante

As métricas de memória por container **só funcionam** com o controlador de
cgroup de memória habilitado no kernel. O Raspberry Pi OS não o habilita por
padrão, e sem ele o Beszel registra `bad memory stats` para todos os
containers. Isso é configurado pelo `setup-host.sh` do repositório
`pihole-docker`, que adiciona `cgroup_enable=memory cgroup_memory=1` ao
`cmdline.txt`.

## Decisões de configuração

- **Porta 8090** — 80 e 443 estão ocupadas pelo Pi-hole, que roda em
  `network_mode: host`.
- **Agente em `network_mode: host`** — precisa enxergar as interfaces reais da
  máquina. Em bridge, mediria apenas a rede virtual do Docker.
- **`docker.sock` somente leitura** — o agente só precisa listar containers e
  ler status. Acesso de escrita ao socket equivale a root no host.
- **Hub em bridge** — não há motivo para ele compartilhar a rede do host; a
  porta publicada basta.

## Segurança

- O painel é **HTTP sem TLS**: a senha trafega em texto claro na rede local.
  Aceitável para acesso restrito à LAN; repensar se for exposto pela VPN.
- **O primeiro acesso cria a conta de administrador.** Enquanto ninguém a criar,
  qualquer pessoa na rede pode se tornar admin — criar logo após subir o hub.
- O `.env` e os diretórios `data/` e `agent_data/` ficam fora do Git.

## Alertas

São dois mecanismos, e a divisão não é arbitrária.

**Beszel** cobre problemas com o Pi ligado: container parado, CPU, memória,
disco ou temperatura fora do normal. Configurado em *Settings → Notifications*
com uma URL Shoutrrr do Telegram, e por sistema no ícone de sino.

**`healthcheck-ping.sh`** cobre o que o Beszel não alcança. Como o hub roda no
próprio Pi que monitora, ele morre junto com a máquina e não avisa ninguém. O
script inverte a lógica: envia um sinal de vida a cada 5 minutos para o
Healthchecks.io, e **o silêncio é que dispara o alerta** — quem avisa está fora
de casa.

O script não se limita a dizer "estou ligado": ele consulta o DNS antes, e
sinaliza falha se o Pi-hole não responder. Um Pi ligado com o DNS quebrado dá o
mesmo prejuízo que um Pi desligado.

Agendamento (cron do usuário, sem privilégios):

```
*/5 * * * * /home/admin/docker/beszel/healthcheck-ping.sh
```

Com *Period* de 10 minutos e *Grace Time* de 5 no Healthchecks, há margem para
duas tentativas antes do alarme — evita alerta falso por falha de rede passageira.

## Escrita no cartão SD

O histórico é gravado continuamente em SQLite dentro de `data/`. Como o sistema
roda em cartão SD, vale revisar a retenção de métricas no painel
(*Settings → Data retention*) se o volume crescer.
