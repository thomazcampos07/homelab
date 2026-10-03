#!/usr/bin/env bash
# Backup semanal do Pi para o Google Drive, criptografado pelo rclone.
#
# Leva o que o Git nao guarda: .env de cada servico, chaves do WireGuard, dados
# do Beszel, export Teleporter do Pi-hole e a crontab. As receitas (compose,
# scripts) ja estao versionadas no GitHub e entram so de carona.
#
# O cron chama este script TODO DIA, mas ele so faz o backup se o ultimo com
# sucesso tiver mais de 6 dias. Assim, se o Pi estiver desligado no dia
# marcado, o backup roda no dia seguinte em vez de pular uma semana.
# Use --force para rodar agora independentemente disso.
set -euo pipefail

DIR=/home/admin/docker/backup
MARK="$DIR/last-success"
MIN_AGE_DAYS=6
KEEP=8w          # retencao no Drive
REMOTE=pi-backup:

cd "$DIR"

if [[ "${1:-}" != "--force" && -f "$MARK" ]] &&
   [[ -z "$(find "$MARK" -mtime +"$((MIN_AGE_DAYS - 1))")" ]]; then
  exit 0
fi

# Le so a variavel necessaria em vez de dar source no .env
HC_PING_URL=$(grep -m1 -E '^HC_PING_URL=' .env 2>/dev/null | cut -d= -f2- || true)
ping_hc() { [[ -n "$HC_PING_URL" ]] && curl -fsS -m 10 --retry 3 "$HC_PING_URL$1" >/dev/null || true; }

cleanup() {
  # O Beszel nunca pode ficar parado por causa de uma falha no meio do caminho
  docker start beszel >/dev/null 2>&1 || true
  # Esvazia em vez de apagar: se as pastas sumirem, o proximo `docker compose
  # run` (ate um manual, de restauracao) as recria como root e o rclone, que
  # roda como admin, nao consegue gravar nelas.
  find staging out -mindepth 1 -delete 2>/dev/null || true
}
fail() { echo "backup falhou na linha $1" >&2; ping_hc /fail; }
trap cleanup EXIT
trap 'fail $LINENO' ERR

ping_hc /start
# Criar antes do compose: pasta de bind mount inexistente o Docker cria como root
rm -rf staging out && mkdir -p staging out rclone

# Pi-hole: o Teleporter e a forma consistente de exportar config, listas e
# clientes. Os bancos SQLite crus copiados com o FTL rodando podem sair corrompidos.
tp=$(docker exec -w /tmp pihole pihole-FTL --teleporter | tail -n1)
docker cp "pihole:/tmp/$tp" staging/pihole-teleporter.zip
docker exec pihole rm -f "/tmp/$tp"

crontab -l > staging/crontab.txt

# Beszel: para alguns segundos para o SQLite fechar limpo antes da copia
docker stop beszel >/dev/null

file="pi-backup-$(date +%F).tar.gz"
docker compose run --rm -T --user 0:0 --entrypoint tar rclone \
  -czf "/out/$file" -C /backup \
  --exclude=docker/backup \
  --exclude=docker/pihole/etc-pihole \
  --exclude=docker/pihole/unbound/keys \
  docker extra

docker start beszel >/dev/null

docker compose run --rm -T rclone copy "/out/$file" "$REMOTE"
docker compose run --rm -T rclone delete "$REMOTE" --min-age "$KEEP"

touch "$MARK"
ping_hc ""
echo "backup enviado: $file"
