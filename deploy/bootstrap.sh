#!/usr/bin/env bash
# Liga a esteira de deploy. Roda UMA vez, no PC, pelo Git Bash, a partir da
# raiz do repo (e de novo para trocar a chave de deploy ou o peer).
#
#   ./deploy/bootstrap.sh
#
# O que faz:
#   1. Cria o Environment "production" no GitHub, liberado so para a main
#   2. Cria o peer "github" no WireGuard do Pi e guarda a config dele
#      (restrita a 192.168.15.5) no secret WG_CLIENT_CONF
#   3. Gera a chave de deploy, instala o receiver no Pi e guarda a chave
#      privada e a host key do Pi nos secrets
#   4. Copia cada valor dos .env do Pi direto para os secrets, sem passar pela
#      tela, seguindo o deploy/env-manifest
#   5. Pergunta (opcional) o token e o chat ID do Telegram
#
# O passo 2 recria o container do WireGuard: a VPN cai por alguns segundos.
set -euo pipefail

PI=admin@192.168.15.5
REPO=thomazcampos07/homelab
ENV_NAME=production

GH=gh
command -v gh >/dev/null 2>&1 || GH="/c/Program Files/GitHub CLI/gh.exe"
cd "$(dirname "$0")/.."

say() { printf '\n==> %s\n' "$*"; }
put_secret() { "$GH" secret set "$1" --env "$ENV_NAME" -R "$REPO" >/dev/null; echo "    secret $1 gravado"; }

say "1/5 Environment $ENV_NAME (deploy so a partir da main)"
"$GH" api -X PUT "repos/$REPO/environments/$ENV_NAME" --input - >/dev/null <<'JSON'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
if ! "$GH" api "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" --jq '.branch_policies[].name' | grep -qx main; then
  "$GH" api -X POST "repos/$REPO/environments/$ENV_NAME/deployment-branch-policies" -f name=main -f type=branch >/dev/null
fi
# Primeiros deploys so mostram o que mudaria. Depois de conferir:
#   gh variable delete DEPLOY_DRY_RUN -R thomazcampos07/homelab
if [[ ! -f "$HOME/.homelab-deploy-bootstrapped" ]]; then
  "$GH" variable set DEPLOY_DRY_RUN --body true -R "$REPO"
  echo "    DEPLOY_DRY_RUN=true (todo deploy em dry-run ate voce apagar a variavel)"
fi
echo "    ok"

say "2/5 Peer github no WireGuard (a VPN pisca)"
# shellcheck disable=SC2016 # expandido no Pi
ssh "$PI" 'cd ~/docker/wireguard &&
  if grep -Eq "^WG_PEERS=(.*,)?github(,|$)" .env; then echo "    peer ja existe";
  else cp -p .env .env.antes-do-peer-github && sed -i "/^WG_PEERS=/ s/\$/,github/" .env && docker compose up -d; fi
  for _ in $(seq 30); do [ -f config/peer_github/peer_github.conf ] && exit 0; sleep 2; done
  echo "peer_github.conf nao apareceu" >&2; exit 1'
# Runner so precisa alcancar o SSH do Pi: nada de rota padrao nem DNS do Pi-hole
ssh "$PI" 'sed -e "s#^AllowedIPs.*#AllowedIPs = 192.168.15.5/32#" -e "/^DNS/d" ~/docker/wireguard/config/peer_github/peer_github.conf' |
  put_secret WG_CLIENT_CONF
echo "    IP do peer: $(ssh "$PI" 'grep -m1 ^Address ~/docker/wireguard/config/peer_github/peer_github.conf' | cut -d= -f2)"

say "3/5 Chave de deploy e receiver"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
ssh-keygen -q -t ed25519 -N '' -C homelab-deploy -f "$tmp/key"
git archive HEAD deploy | ssh "$PI" "rm -rf ~/docker/.deploy/setup && mkdir -p ~/docker/.deploy/setup && tar -x -C ~/docker/.deploy/setup && ~/docker/.deploy/setup/deploy/install.sh '$(cat "$tmp/key.pub")'"
put_secret DEPLOY_SSH_KEY <"$tmp/key"
ssh-keyscan -t ed25519 192.168.15.5 2>/dev/null | put_secret PI_SSH_HOST_KEY

say "4/5 Valores dos .env do Pi para os secrets"
while read -r svc key name; do
  [[ -z "$svc" || "$svc" == \#* ]] && continue
  val=$(ssh -n "$PI" "grep -m1 '^$key=' ~/docker/$svc/.env | cut -d= -f2-")
  [[ -n "$val" ]] || { echo "    $svc/.env nao tem $key" >&2; exit 1; }
  printf '%s' "$val" | put_secret "$name"
done <deploy/env-manifest
unset val
if ssh -n "$PI" 'test -s ~/docker/pihole/clients.list'; then
  ssh -n "$PI" 'cat ~/docker/pihole/clients.list' | put_secret PIHOLE_CLIENTS_LIST
fi

say "5/5 Telegram (opcional, Enter para pular)"
read -rsp "    Token do bot (do BotFather): " tg_token; echo
if [[ -n "$tg_token" ]]; then
  read -rp "    Chat ID: " tg_chat
  printf '%s' "$tg_token" | put_secret TELEGRAM_BOT_TOKEN
  printf '%s' "$tg_chat" | put_secret TELEGRAM_CHAT_ID
fi
unset tg_token

touch "$HOME/.homelab-deploy-bootstrapped"
say "Pronto. Secrets no Environment $ENV_NAME:"
"$GH" secret list --env "$ENV_NAME" -R "$REPO"
