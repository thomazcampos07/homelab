#!/usr/bin/env bash
# Cadastra os clientes nomeados no Pi-hole. Idempotente: pode rodar de novo
# sem duplicar. Os clientes ficam no gravity.db, que nao e versionado, entao
# este script e a fonte da verdade para recria-los num Pi novo.
#
# Cadastro por MAC, nao por IP: o roteador reatribui IPs e o MAC (com o
# "Endereco Wi-Fi privado" do iPhone em Fixo) nao muda nesta rede.
set -euo pipefail

# MAC|nome  (IP reservado no roteador so como referencia)
CLIENTS=(
  "AA:BB:CC:DD:EE:01|iPhone do Thomaz"     # 192.168.15.21
  "AA:BB:CC:DD:EE:02|Notebook do Thomaz"   # 192.168.15.20
)

sql=""
for entry in "${CLIENTS[@]}"; do
  mac="${entry%%|*}"
  name="${entry#*|}"
  sql+="insert into client (ip, comment) values ('$mac', '$name')
        on conflict(ip) do update set comment = excluded.comment;"
done

docker exec pihole pihole-FTL sqlite3 /etc/pihole/gravity.db "$sql"
docker exec pihole pihole reloadlists
docker exec pihole pihole-FTL sqlite3 /etc/pihole/gravity.db \
  "select ip, comment from client order by id;"
