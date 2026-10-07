#!/usr/bin/env bash
# Confere se o dominio DuckDNS ainda aponta para o IP publico da casa e, se
# sim, manda sinal de vida para um check proprio no Healthchecks.io.
#
# Sem DDNS certo a VPN some para os aparelhos fora de casa e o deploy pelo
# GitHub Actions nao alcanca o Pi. Em 2026-09/10 o container duckdns ficou 12
# dias de pe, sem erro visivel, e sem atualizar o IP: so este teste de ponta a
# ponta pega esse caso.
#
# Divergencia NAO manda /fail: depois de uma troca de IP da operadora o
# DuckDNS leva alguns minutos para atualizar. O script so deixa de pingar, e a
# tolerancia do check no Healthchecks decide quando o silencio vira alerta.
#
# Agendado no cron do admin a cada 5 min (ver README).
set -uo pipefail

ENV_FILE="${DDNS_CHECK_ENV:-/home/admin/docker/wireguard/.env}"

# Le so as variaveis necessarias em vez de dar source no .env
get() { grep -m1 -E "^$1=" "$ENV_FILE" 2>/dev/null | cut -d= -f2-; }
HC_URL=$(get DDNS_HC_PING_URL)
DOMAIN=$(get DDNS_DOMAIN)
: "${HC_URL:?DDNS_HC_PING_URL nao encontrada em $ENV_FILE}"
: "${DOMAIN:?DDNS_DOMAIN nao encontrada em $ENV_FILE}"

is_ipv4() { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }

# Mais de uma fonte: um servico fora do ar nao pode virar alarme falso
public_ip() {
  local url ip
  for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
    ip=$(curl -4 -fsS -m 10 "$url" 2>/dev/null | tr -d '[:space:]')
    is_ipv4 "$ip" && { echo "$ip"; return 0; }
  done
  return 1
}

if ! public=$(public_ip); then
  echo "nao consegui descobrir o IP publico; sem ping" >&2
  exit 0
fi

dns=$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR == 1 { print $1 }')

if [[ "$dns" == "$public" ]]; then
  curl -fsS -m 10 --retry 3 "$HC_URL" >/dev/null
else
  echo "DDNS desatualizado: dominio em ${dns:-nada}, IP publico $public; sem ping" >&2
fi
