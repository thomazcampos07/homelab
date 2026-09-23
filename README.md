# Beszel — monitoramento do Raspberry Pi 4

Monitoramento de CPU, memória, disco, rede, temperatura e containers do
Raspberry Pi 4 (`192.168.15.5`), com histórico e alertas.

Painel em **http://192.168.15.5:8090**.

São dois componentes: o **hub** (interface web e banco de histórico) e o
**agente** (coleta as métricas da máquina). Ambos rodam no mesmo Pi, mas o hub
pode monitorar outras máquinas depois — basta rodar mais agentes.

## Subir

```bash
cp .env.example .env
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

## Escrita no cartão SD

O histórico é gravado continuamente em SQLite dentro de `data/`. Como o sistema
roda em cartão SD, vale revisar a retenção de métricas no painel
(*Settings → Data retention*) se o volume crescer.
