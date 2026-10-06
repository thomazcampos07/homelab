#!/usr/bin/env bash
# Instala no Pi a porta de entrada da esteira: o receiver em
# ~/.local/bin/homelab-deploy e a chave de deploy no authorized_keys, presa a
# ele por command= forcado. Roda no Pi; o bootstrap.sh chama sozinho.
# Idempotente e sem sudo.
#
#   install.sh "ssh-ed25519 AAAA... homelab-deploy"
set -euo pipefail

PUBKEY=${1:?uso: install.sh "<chave publica ed25519 com comentario homelab-deploy>"}
[[ "$PUBKEY" =~ ^ssh-ed25519\ [A-Za-z0-9+/=]+\ homelab-deploy$ ]] ||
  { echo "chave invalida: esperado 'ssh-ed25519 <base64> homelab-deploy'" >&2; exit 1; }

HERE=$(cd "$(dirname "$0")" && pwd)
BIN=$HOME/.local/bin/homelab-deploy
AK=$HOME/.ssh/authorized_keys

mkdir -p "$HOME/.local/bin" "$HOME/docker/.deploy/runs"
chmod 700 "$HOME/docker/.deploy"
install -m 755 "$HERE/receiver.sh" "$BIN"
echo "receiver instalado em $BIN"

# restrict: sem shell interativo, sem encaminhamento de porta, agente ou X11.
# command=: qualquer comando pedido vira uma chamada ao receiver.
line="restrict,command=\"$BIN\" $PUBKEY"

# Troca a chave de deploy anterior (se houver) sem tocar nas outras linhas.
# Reescreve com cat > em vez de mv para manter dono e permissao do arquivo.
tmp=$(mktemp)
grep -v ' homelab-deploy$' "$AK" >"$tmp" || true
echo "$line" >>"$tmp"
cat "$tmp" >"$AK"
rm -f "$tmp"
chmod 600 "$AK"
echo "chave de deploy registrada ($(grep -c . "$AK") chaves no authorized_keys)"
