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
cd "$DIR"
mkdir -p rclone staging out
chmod 700 rclone

[[ -f .env ]] || { echo "Crie o .env a partir do .env.example antes." >&2; exit 1; }

echo "Cole o que o 'rclone authorize' imprimiu no PC (entre ---> e <---End paste):"
read -r AUTH
read -rsp "Senha da criptografia (guarde no gerenciador de senhas): " PASS; echo
read -rsp "Repita a senha: " PASS2; echo
[[ "$PASS" == "$PASS2" ]] || { echo "As senhas nao conferem." >&2; exit 1; }

# Grava o rclone.conf direto em vez de usar `rclone config create`: com o
# remote do Drive, o config create insiste em abrir o fluxo OAuth no navegador
# mesmo recebendo o token, e no Pi nao ha navegador.
# A senha vai pelo stdin para nao aparecer na lista de processos.
#
# Chamado com opcoes em base64, o `rclone authorize` devolve tambem em base64
# um JSON com client_id, client_secret e o token. Aceita esse formato ou o
# token JSON puro ({"access_token":...}).
DRIVE_CREDS=$(printf '%s' "$AUTH" | python3 -c '
import base64, json, sys
raw = sys.stdin.read().strip()
d = json.loads(raw if raw.startswith("{") else base64.b64decode(raw))
tok = d.get("token", d) if "access_token" not in d else d
tok = tok if isinstance(tok, str) else json.dumps(tok)
for k in ("client_id", "client_secret"):
    if d.get(k):
        print(f"{k} = {d[k]}")
print(f"token = {tok}")
')
OBSCURED=$(printf '%s' "$PASS" | docker compose run --rm -T rclone obscure -)

# Nomes de arquivo em claro (so o conteudo e criptografado): da para ver no
# Drive de que dia e cada backup sem precisar do rclone.
umask 077
cat > rclone/rclone.conf <<CONF
[gdrive]
type = drive
scope = drive.file
$DRIVE_CREDS

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
