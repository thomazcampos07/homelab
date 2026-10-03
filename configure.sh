#!/usr/bin/env bash
# Configuracao inicial, feita uma vez (e de novo num Pi reinstalado).
# Interativo: rodar com `ssh -t`, porque pede o token e a senha.
#
#   1. Cria os remotes do rclone: "gdrive" (Google Drive, so os arquivos que o
#      proprio rclone criar) e "pi-backup" (camada de criptografia sobre ele)
#   2. Agenda o backup.sh no cron, sem duplicar a linha
set -euo pipefail

DIR=/home/admin/docker/backup
FOLDER="Backups Raspberry Pi"
# Client OAuth proprio (projeto "rclone-pi" no Google Cloud). O compartilhado do
# rclone esta sendo desativado. O ID nao e segredo; o secret e pedido abaixo.
CLIENT_ID="<CLIENT_ID>.apps.googleusercontent.com"
cd "$DIR"
mkdir -p rclone staging out
chmod 700 rclone

[[ -f .env ]] || { echo "Crie o .env com HC_PING_URL=<url do Healthchecks> antes (ver README)." >&2; exit 1; }

echo "Cole o que o 'rclone authorize' imprimiu no PC (entre ---> e <---End paste):"
read -r AUTH
read -rsp "Client secret do Google (comeca com GOCSPX-): " CLIENT_SECRET; echo
# Colar o bloco do token aqui por engano (ficou na area de transferencia) da
# invalid_client so na renovacao, uma hora depois. Melhor barrar na hora.
[[ "$CLIENT_SECRET" =~ ^GOCSPX-[A-Za-z0-9_-]{20,40}$ ]] ||
  { echo "Isso nao parece o client secret (GOCSPX-..., ~35 caracteres)." >&2; exit 1; }
read -rsp "Senha da criptografia (guarde no gerenciador de senhas): " PASS; echo
read -rsp "Repita a senha: " PASS2; echo
[[ "$PASS" == "$PASS2" ]] || { echo "As senhas nao conferem." >&2; exit 1; }

# Grava o rclone.conf direto em vez de usar `rclone config create`: com o
# remote do Drive, o config create insiste em abrir o fluxo OAuth no navegador
# mesmo recebendo o token, e no Pi nao ha navegador.
# A senha vai pelo stdin para nao aparecer na lista de processos.
#
# O `rclone authorize` devolve o token em base64 dentro de um JSON (que NAO
# traz o client_id/secret, mesmo quando foram passados), ou o token JSON puro.
# Aceita os dois formatos e extrai so o token.
DRIVE_TOKEN=$(printf '%s' "$AUTH" | python3 -c '
import base64, json, sys
raw = sys.stdin.read().strip()
d = json.loads(raw if raw.startswith("{") else base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4)))
tok = d.get("token", d) if "access_token" not in d else d
tok = tok if isinstance(tok, str) else json.dumps(tok)
print(tok)
')
OBSCURED=$(printf '%s' "$PASS" | docker compose run --rm -T rclone obscure -)

# Nomes de arquivo em claro (so o conteudo e criptografado): da para ver no
# Drive de que dia e cada backup sem precisar do rclone.
umask 077
cat > rclone/rclone.conf <<CONF
[gdrive]
type = drive
scope = drive.file
client_id = $CLIENT_ID
client_secret = $CLIENT_SECRET
token = $DRIVE_TOKEN

[pi-backup]
type = crypt
remote = gdrive:$FOLDER
password = $OBSCURED
filename_encryption = off
directory_name_encryption = false
CONF

docker compose run --rm -T rclone mkdir "pi-backup:"
echo "rclone configurado. Pasta no Drive: $FOLDER"

CRON_LINE="30 3 * * * $DIR/backup.sh 2>&1 | systemd-cat -t pi-backup"
if ! crontab -l 2>/dev/null | grep -qF "$DIR/backup.sh"; then
  (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
  echo "cron agendado: todo dia 03:30 (faz backup se o ultimo tiver mais de 6 dias)"
fi
