#!/usr/bin/env bash
# Monta os .env de cada servico a partir do env-manifest.
#
#   render-env.sh <pasta-de-saida>            valores reais, lidos do ambiente
#   render-env.sh <pasta-de-saida> --dummy    valores ficticios, para o CI
#
# Cada secret chega como variavel de ambiente com o proprio nome, passada uma
# a uma no deploy.yml (o CI confere que a lista bate com o env-manifest).
# Nada aqui imprime valor: os logs do Actions sao publicos.
#
# Saida: <pasta>/<servico>.env no formato CHAVE=valor, sem aspas, porque o
# healthcheck-ping.sh e o backup.sh leem com grep | cut e o BESZEL_KEY tem
# espaco. Se o secret PIHOLE_CLIENTS_LIST existir, vira <pasta>/clients.list.
set -euo pipefail

OUT=${1:?uso: render-env.sh <pasta-de-saida> [--dummy]}
DUMMY=${2:-}
MANIFEST="$(dirname "$0")/env-manifest"

mkdir -p "$OUT"
umask 077

secret() { printf '%s' "${!1:-}"; }

missing=()
while read -r svc key name; do
  [[ -z "$svc" || "$svc" == \#* ]] && continue
  if [[ "$DUMMY" == "--dummy" ]]; then
    value="dummy-$name"
  else
    value=$(secret "$name")
  fi
  # Secret vazio nunca vira .env: um PIHOLE_PASSWORD= vazio deixaria o painel
  # do Pi-hole sem senha.
  if [[ -z "$value" ]]; then
    missing+=("$name")
    continue
  fi
  if [[ "$value" == *$'\n'* ]]; then
    echo "secret $name tem quebra de linha; .env aceita uma linha por chave" >&2
    exit 1
  fi
  printf '%s=%s\n' "$key" "$value" >>"$OUT/$svc.env"
done <"$MANIFEST"

if ((${#missing[@]})); then
  echo "secrets ausentes ou vazios: ${missing[*]}" >&2
  exit 1
fi

if [[ "$DUMMY" != "--dummy" ]]; then
  clients=$(secret PIHOLE_CLIENTS_LIST)
  [[ -n "$clients" ]] && printf '%s\n' "$clients" >"$OUT/clients.list"
fi

echo ".env montados: $(cd "$OUT" && ls | tr '\n' ' ')"
