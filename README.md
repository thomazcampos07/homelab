# Backup do Raspberry Pi → Google Drive

Backup semanal, criptografado, de tudo que **não** está no Git: os `.env` de
cada serviço, as chaves do WireGuard, os dados do Beszel, o export Teleporter
do Pi-hole e a crontab. Se o cartão SD morrer, as receitas voltam do GitHub e
o estado volta daqui.

Roda no Pi em `~/docker/backup/`, usando o rclone em container
(`docker compose run`), sem nada instalado no host.

## Como funciona

- O cron chama `backup.sh` **todo dia às 03:30**, mas ele só faz backup se o
  último com sucesso tiver mais de 6 dias. Se o Pi estiver desligado no dia,
  o backup sai no dia seguinte em vez de pular a semana.
- O arquivo `pi-backup-AAAA-MM-DD.tar.gz` é criptografado pelo rclone
  (remote `crypt`) **antes** de sair do Pi e vai para a pasta
  *Backups Raspberry Pi* no Drive. Os nomes ficam legíveis, o conteúdo não.
- Retenção de **8 semanas**: os mais antigos são apagados a cada execução.
- O rclone acessa o Drive com escopo `drive.file`: enxerga só os arquivos que
  ele mesmo criou, não o resto do seu Drive.
- O Beszel é parado por alguns segundos durante a cópia para o banco SQLite
  sair consistente. Do Pi-hole vai o Teleporter, não os bancos crus.
- O Healthchecks.io recebe `/start`, sucesso ou `/fail`. Se nada chegar em
  9 dias, avisa no Telegram.

Ficam de fora de propósito: `etc-pihole/` (coberto pelo Teleporter), o
`root.key` do Unbound (cada instalação gera o seu) e a própria pasta
`backup/`, que contém o `rclone.conf` com o token do Drive.

## ⚠️ A senha da criptografia

Ela fica no `rclone.conf` **dentro do Pi**. Se o cartão morrer, ela morre
junto — e sem ela os backups no Drive são ilegíveis. **Guarde-a no gerenciador
de senhas.** É o único ponto deste setup que não se recupera de outro lugar.

## Instalação

1. No **PC Windows**, gerar o token do Google Drive (abre o navegador para
   autorizar):
   ```powershell
   winget install Rclone.Rclone
   rclone authorize "drive" "eyJzY29wZSI6ImRyaXZlLmZpbGUifQ"
   ```
   O segundo argumento é `{"scope":"drive.file"}` em base64. Copiar a linha
   `{...}` que ele imprime no final.
2. No Healthchecks.io, criar um check *Backup semanal* com período de
   **7 dias** e tolerância de **2 dias**, ligado ao Telegram.
3. No Pi:
   ```bash
   cd ~/docker/backup
   cp .env.example .env && chmod 600 .env   # colar a URL do check
   ```
4. Do PC, rodar a configuração (interativa — pede o token e a senha):
   ```bash
   ssh -t admin@192.168.15.5 ~/docker/backup/configure.sh
   ```
5. Testar um backup na hora:
   ```bash
   ~/docker/backup/backup.sh --force
   ```

## Restaurar

Num Pi com o `configure.sh` já rodado (mesma senha):

```bash
cd ~/docker/backup
docker compose run --rm rclone ls pi-backup:
docker compose run --rm rclone copy pi-backup:pi-backup-AAAA-MM-DD.tar.gz /out
mkdir -p /tmp/restore && tar -xzf out/pi-backup-AAAA-MM-DD.tar.gz -C /tmp/restore
```

O `.tar.gz` tem duas pastas: `docker/` (espelho de `~/docker`, com os `.env` e
dados) e `extra/` (`pihole-teleporter.zip` e `crontab.txt`). Copiar o que
precisar de volta, importar o Teleporter pelo painel do Pi-hole
(*Settings → Teleporter*) e recriar a crontab com `crontab extra/crontab.txt`.

Sem Pi nenhum, dá para restaurar no PC: `rclone config` com os mesmos dois
remotes (`gdrive` e `pi-backup`, mesma senha) e `rclone copy`.

## Logs

```bash
journalctl -t pi-backup
```
