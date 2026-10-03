#!/usr/bin/env bash
# Cadastra os clientes nomeados no Pi-hole. Idempotente: pode rodar de novo
# sem duplicar. Os clientes ficam no gravity.db, que nao e versionado, entao
# este script e a fonte da verdade para recria-los num Pi novo.
#
# Cadastro por MAC, nao por IP: o roteador reatribui IPs e o MAC (com o
# "Endereco Wi-Fi privado" do iPhone em Fixo) nao muda nesta rede.
#
# A lista fica em clients.list, ao lado do script e fora do Git (ver
# clients.list.example): uma linha "MAC|nome" por aparelho.
set -euo pipefail

LIST="$(dirname "$0")/clients.list"
[[ -f "$LIST" ]] || { echo "Crie o $LIST a partir do clients.list.example." >&2; exit 1; }

sql=""
while IFS= read -r entry; do
  entry="${entry%%#*}"
  entry="${entry#"${entry%%[![:space:]]*}"}"
  entry="${entry%"${entry##*[![:space:]]}"}"
  [[ -n "$entry" ]] || continue
  mac="${entry%%|*}"
  name="${entry#*|}"
  sql+="insert into client (ip, comment) values ('$mac', '$name')
        on conflict(ip) do update set comment = excluded.comment;"
done < "$LIST"

docker exec pihole pihole-FTL sqlite3 /etc/pihole/gravity.db "$sql"
docker exec pihole pihole reloadlists
docker exec pihole pihole-FTL sqlite3 /etc/pihole/gravity.db \
  "select ip, comment from client order by id;"
