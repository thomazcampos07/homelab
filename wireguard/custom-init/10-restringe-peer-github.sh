#!/bin/bash
# Roda como root dentro do container, a cada inicializacao, antes do tunel
# subir (a imagem do linuxserver executa tudo que esta em /custom-cont-init.d).
#
# Limita o peer "github" (runner do deploy no GitHub Actions) ao SSH do Pi.
# Os outros peers continuam com acesso total. Se a config desse peer vazar,
# quem a tiver so chega a porta 22, onde ainda precisa da chave de deploy,
# que por sua vez so chama o receiver.
#
# Por que aqui e nao no template do wg0.conf: a imagem so regenera o wg0.conf
# quando PEERS, SERVERURL etc. mudam, entao trocar o template nao teria efeito.
# As regras entram com -A antes de o wg-quick adicionar o ACCEPT generico do
# PostUp, entao ficam na frente dele na chain FORWARD.
set -uo pipefail

PEER_CONF=/config/peer_github/peer_github.conf
PI=192.168.15.5

if [[ ! -f "$PEER_CONF" ]]; then
  echo "peer github ainda nao existe; nada a restringir"
  exit 0
fi

# IP do peer lido da propria config, para nao divergir se ela for regenerada
PEER_IP=$(sed -n 's/^Address *= *\([0-9.]*\).*/\1/p' "$PEER_CONF" | head -1)
if [[ ! "$PEER_IP" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
  echo "nao achei o IP do peer github em $PEER_CONF" >&2
  exit 1
fi

add() { iptables -C FORWARD "$@" 2>/dev/null || iptables -A FORWARD "$@"; }
add -i wg0 -s "$PEER_IP" -d "$PI" -p tcp --dport 22 -j ACCEPT
add -i wg0 -s "$PEER_IP" -j DROP
echo "peer github ($PEER_IP) restrito a $PI:22"
