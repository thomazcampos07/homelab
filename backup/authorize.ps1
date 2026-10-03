# Gera no PC o token do Google Drive para o rclone do Pi.
# Rodar no PowerShell do Windows (precisa do rclone: winget install Rclone.Rclone).
# Abre o navegador para autorizar; colar o bloco impresso no configure.sh do Pi.
#
# O client ID e o secret sao do projeto "rclone-pi" no Google Cloud. Ficam
# fora do Git e sao pedidos na hora.

$ClientId = Read-Host "Client ID (...apps.googleusercontent.com)"

$secure = Read-Host "Client secret" -AsSecureString
$ClientSecret = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
  [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))

$opts = @{ client_id = $ClientId; client_secret = $ClientSecret; scope = "drive.file" } |
  ConvertTo-Json -Compress
# O rclone le base64 "URL-safe" sem padding: troca + e / por - e _, tira o =
$b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($opts))
$b64 = $b64.TrimEnd('=').Replace('+', '-').Replace('/', '_')

rclone authorize "drive" $b64
