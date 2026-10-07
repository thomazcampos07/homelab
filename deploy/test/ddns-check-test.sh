#!/usr/bin/env bash
# Teste do wireguard/ddns-check.sh com curl e getent falsos.
#
#   docker run --rm -v "$PWD:/src:ro" debian:trixie-slim bash /src/deploy/test/ddns-check-test.sh
#
# Escreve em /stub e /tmp: nunca rodar fora de um container.
set -uo pipefail
[[ -f /.dockerenv ]] || { echo "rodar so dentro de um container descartavel" >&2; exit 2; }

mkdir -p /stub
export PATH=/stub:$PATH
# IPs de documentacao (RFC 5737), nunca enderecos reais
cat >/stub/curl <<'EOF'
#!/bin/bash
url=${*: -1}
case "$url" in
  https://hc.example/*) echo "$url" >>/tmp/pings ;;
  https://api.ipify.org) [[ -n "${FAKE_IPIFY:-}" ]] && echo "$FAKE_IPIFY" || exit 7 ;;
  https://ifconfig.me/ip) [[ -n "${FAKE_IFCONFIG:-}" ]] && echo "$FAKE_IFCONFIG" || exit 7 ;;
  *) exit 7 ;;
esac
EOF
cat >/stub/getent <<'EOF'
#!/bin/bash
[[ -n "${FAKE_DNS:-}" ]] && printf '%s STREAM %s\n%s DGRAM\n' "$FAKE_DNS" "$3" "$FAKE_DNS" || exit 2
EOF
chmod +x /stub/*

export DDNS_CHECK_ENV=/tmp/env
printf 'DUCKDNS_TOKEN=x\nDDNS_DOMAIN=casa.example\nDDNS_HC_PING_URL=https://hc.example/abc\n' >"$DDNS_CHECK_ENV"

FAILS=0
run() {  # $1 = descricao, $2 = pings esperados, $3 = rc esperado ("erro" = qualquer != 0), resto = variaveis
  local desc=$1 want=$2 want_rc=$3 rc got; shift 3
  rm -f /tmp/pings
  env "$@" bash /src/wireguard/ddns-check.sh 2>/tmp/err; rc=$?
  got=0; [[ -f /tmp/pings ]] && got=$(wc -l </tmp/pings)
  [[ "$want_rc" == erro && "$rc" != 0 ]] && rc=erro
  if [[ "$got" == "$want" && "$rc" == "$want_rc" ]]; then
    echo "  PASS $desc"
  else
    echo "  FAIL $desc (pings $got, rc $rc): $(cat /tmp/err)"
    FAILS=$((FAILS + 1))
  fi
}

run "dominio no IP certo: pinga" 1 0 FAKE_IPIFY=192.0.2.10 FAKE_DNS=192.0.2.10
run "dominio desatualizado: nao pinga" 0 0 FAKE_IPIFY=192.0.2.10 FAKE_DNS=198.51.100.7
run "dominio nao resolve: nao pinga" 0 0 FAKE_IPIFY=192.0.2.10
run "ipify fora, ifconfig.me responde: pinga" 1 0 FAKE_IFCONFIG=192.0.2.10 FAKE_DNS=192.0.2.10
run "nenhuma fonte de IP: nao pinga" 0 0 FAKE_DNS=192.0.2.10
run "resposta que nao e IP: nao pinga" 0 0 FAKE_IPIFY="<html>erro</html>" FAKE_DNS=192.0.2.10
run "pinga a URL do .env" 1 0 FAKE_IPIFY=192.0.2.10 FAKE_DNS=192.0.2.10
grep -qx https://hc.example/abc /tmp/pings && echo "  PASS URL certa" || { echo "  FAIL URL"; FAILS=$((FAILS + 1)); }

printf 'DDNS_DOMAIN=casa.example\n' >"$DDNS_CHECK_ENV"
run "sem DDNS_HC_PING_URL no .env: erro" 0 erro FAKE_IPIFY=192.0.2.10 FAKE_DNS=192.0.2.10

echo "== falhas: $FAILS"
exit $FAILS
