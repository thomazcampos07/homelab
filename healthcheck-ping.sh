#!/usr/bin/env bash
# Sinal de vida periodico para o Healthchecks.io (dead man's switch).
#
# O Beszel roda no proprio Pi que monitora, entao nao consegue avisar quando a
# maquina cai — ele cai junto. Este script resolve isso pelo avesso: quem alerta
# e um servico externo, e o gatilho e o SILENCIO. Se o ping parar de chegar, o
# Healthchecks avisa.
#
# So pinga se o DNS estiver realmente respondendo. Assim o alerta cobre tanto o
# Pi fora do ar quanto o Pi ligado com o Pi-hole quebrado — que para quem usa a
# rede da o mesmo prejuizo.
set -uo pipefail

ENV_FILE="/home/admin/docker/beszel/.env"

# Le apenas a variavel necessaria em vez de dar source no arquivo: o .env tem
# valores com espaco (a chave do Beszel), que o shell tentaria executar como
# comando. Source tambem executaria qualquer codigo presente no arquivo.
HC_PING_URL=$(grep -m1 -E '^HC_PING_URL=' "$ENV_FILE" 2>/dev/null | cut -d= -f2-)

: "${HC_PING_URL:?HC_PING_URL nao encontrada em $ENV_FILE}"

if docker exec pihole dig @127.0.0.1 google.com +short +time=5 +tries=2 >/dev/null 2>&1; then
  curl -fsS -m 10 --retry 3 "$HC_PING_URL" >/dev/null
else
  # Avisa imediatamente em vez de esperar o timeout do periodo.
  curl -fsS -m 10 --retry 3 "${HC_PING_URL}/fail" >/dev/null
fi
