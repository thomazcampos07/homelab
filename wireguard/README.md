# WireGuard + DuckDNS — Raspberry Pi 4

VPN da casa em container no Raspberry Pi 4 (`192.168.15.5`), com DDNS para
acompanhar o IP público dinâmico da operadora.

O objetivo principal não é só acessar a rede de casa de fora: é **levar o
Pi-hole junto**. Os clientes recebem `192.168.15.5` como DNS e roteiam todo o
tráfego pelo túnel, então o bloqueio de anúncios continua valendo no 4G ou em
Wi-Fi público. O stack de DNS está na pasta `pihole/`.

## Variáveis do `.env`

O `.env` não é versionado. Num Pi reinstalado, ele volta do backup semanal
(`docker/wireguard/.env` dentro do `.tar.gz`, ver pasta `backup/`);
sem backup, criar à mão com as variáveis abaixo e `chmod 600 .env`.

| Variável | Conteúdo |
|---|---|
| `DUCKDNS_SUBDOMAIN` | Subdomínio no DuckDNS, sem `.duckdns.org` |
| `DUCKDNS_TOKEN` | Token da conta DuckDNS |
| `DDNS_DOMAIN` | Domínio completo (`<subdominio>.duckdns.org`), endpoint dos clientes |
| `WG_PEERS` | Perfis separados por vírgula (hoje `celular,notebook`) |

As chaves dos perfis ficam em `config/`, também fora do Git e também no backup.

## Subir

```bash
docker compose up -d
```

## Adicionar um dispositivo

Os perfis são definidos em `WG_PEERS` no `.env`. Para pegar a configuração:

```bash
docker exec wireguard /app/show-peer celular     # QR code no terminal
```

Celular escaneia o QR; notebook importa o arquivo em `config/peer_<nome>/`.

Incluir um novo nome em `WG_PEERS` exige recriar o container
(`docker compose up -d --force-recreate`). Perfis já gerados são preservados.

## Pré-requisitos fora do Git

- **Redirecionamento de porta no roteador**: `UDP 51820` → `192.168.15.5`
- **Subdomínio no DuckDNS** criado manualmente (a API só atualiza IP, não cria)
- Sem CGNAT na conexão — verificado por traceroute: nenhum salto em `100.64.x`

## Decisões de configuração

- **`ALLOWEDIPS: 0.0.0.0/0`** — todo o tráfego do cliente passa pelo túnel. Com
  rota parcial só a rede local seria alcançada, e a navegação continuaria sem
  filtro de anúncios, que é o propósito aqui.
- **`PEERDNS: 192.168.15.5`** — aponta para o Pi-hole, não para o CoreDNS que a
  imagem traz embutido.
- **`listeningMode` do Pi-hole não precisou ser alterado** — o container faz
  MASQUERADE, então as consultas chegam como `172.19.0.2` e o Pi-hole já as trata
  como rede local. Relaxar a configuração dele seria desnecessário.
- **`SYS_MODULE` + `/lib/modules`** — o container carrega o módulo `wireguard`
  no kernel do host. O Raspberry Pi OS traz `CONFIG_WIREGUARD=m`.
- **DuckDNS em container próprio** — o IP público muda sem aviso; sem atualizar
  o subdomínio, os clientes deixam de encontrar o servidor.

## Segurança

O `.env` (token do DuckDNS) e todo o diretório `config/` ficam **fora do Git** —
esse diretório guarda as chaves privadas do servidor e de cada dispositivo.
