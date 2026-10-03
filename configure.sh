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

echo "Cole o token gerado no PC por 'rclone authorize' (a linha {...}):"
read -r TOKEN
read -rsp "Senha da criptografia (guarde no gerenciador de senhas): " PASS; echo
read -rsp "Repita a senha: " PASS2; echo
[[ "$PASS" == "$PASS2" ]] || { echo "As senhas nao conferem." >&2; exit 1; }

docker compose run --rm -T rclone config create gdrive drive \
  scope=drive.file token="$TOKEN" >/dev/null

# Nomes de arquivo em claro (so o conteudo e criptografado): da para ver no
# Drive de que dia e cada backup sem precisar do rclone.
docker compose run --rm -T rclone config create pi-backup crypt \
  remote="gdrive:$FOLDER" password="$PASS" \
  filename_encryption=off directory_name_encryption=false >/dev/null

docker compose run --rm -T rclone mkdir "pi-backup:"
echo "rclone configurado. Pasta no Drive: $FOLDER"

CRON_LINE="30 3 * * * $DIR/backup.sh 2>&1 | systemd-cat -t pi-backup"
if ! crontab -l 2>/dev/null | grep -qF "$DIR/backup.sh"; then
  (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
  echo "cron agendado: todo dia 03:30 (faz backup se o ultimo tiver mais de 6 dias)"
fi
