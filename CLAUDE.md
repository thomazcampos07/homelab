# homelab — instruções para o Claude

Infra do Raspberry Pi 4 (`admin@192.168.15.5`): Pi-hole + Unbound, WireGuard
+ DuckDNS, Beszel e backup, tudo em Docker. Visão geral no `README.md`; cada
pasta de serviço tem README próprio, em português.

## Regras

- **Repo público.** Nada pessoal em arquivo nem em mensagem de commit: MACs,
  domínio DuckDNS, client ID/secret do Google, URLs de ping do Healthchecks,
  tokens. O CI barra com gitleaks (`.gitleaks.toml`); o IP `192.168.15.5` e o
  usuário `admin` podem aparecer.
- **Merge na `main` = deploy no Pi.** Mudança vai por branch + PR e espera os
  5 checks do CI. Merge só quando o Thomaz pedir.
- **Logs do Actions são públicos.** Em workflow e script de deploy: nada de
  `set -x`, `cat` em `.env` ou na config da VPN. Imprimir nomes, nunca valores.
- Serviço novo = pasta nova + entrada em `directories` do
  `.github/dependabot.yml` + linha na tabela do README da raiz. Não criar repo
  novo.
- Imagem sempre com tag pinada, nunca `:latest`.
- Sem `.env.example`: as variáveis ficam numa tabela no README do serviço.
- Variável nova num `.env` = linha no `deploy/env-manifest` + secret no
  Environment `production` + linha no `env:` do passo "Monta o pacote" do
  `deploy.yml`. O CI confere as três.
- O Pi tem 1 GB de RAM e boot por cartão SD: pesar memória e escrita em disco
  antes de propor qualquer coisa.

## Comandos

```bash
# Validação local (o CI roda o mesmo)
git ls-files '*.sh' | xargs shellcheck --severity=warning
docker run --rm -v "$PWD:/src:ro" debian:trixie-slim bash /src/deploy/test/apply-test.sh

# Ver o que está aplicado no Pi
ssh admin@192.168.15.5 'cat ~/docker/.deploy/deployed-sha; docker ps --format "{{.Names}}\t{{.Status}}"'
```

Deploy manual (plano B, só com a esteira fora do ar): enviar a versão
commitada, que é LF, nunca o arquivo do working tree do Windows:
`git show HEAD:<arquivo> | ssh admin@192.168.15.5 'cat > ~/docker/<arquivo>'`.

## Armadilhas já resolvidas

- Script `.sh` novo criado no Windows perde o bit de executável:
  `git update-index --chmod=+x <arquivo>`.
- Nunca dar `source` no `.env` em script shell: há valores com espaço. Extrair
  com `grep`/`cut`.
- O comando `pihole` não existe no host: `docker exec pihole pihole <cmd>`.
- Pi-hole precisa de `network_mode: host` (relatório por cliente). Unbound
  escuta só em `127.0.0.1:5335` (a 5353 é do avahi) e precisa de
  `do-daemonize: no` (imagem distroless).
- O `deploy/receiver.sh` não é atualizado pela esteira: é a âncora de
  confiança. Mudou, reinstalar com `deploy/bootstrap.sh` ou `install.sh`.
- Workflow com `toJSON(secrets)` é bloqueado pelo GitHub: passar cada secret
  pelo nome.
- O cloud-init roda a cada boot e lê `/boot/firmware/user-data`: mudança de
  hostname feita só com `hostnamectl` é revertida no reinício.
- Ausência de log não prova evento. Antes de concluir o que aconteceu com o
  Pi, conferir se a fonte (journal, Beszel) poderia ter registrado aquilo.
  Para saber quando o Pi ligou, usar `uptime`: sem RTC, o horário de boot do
  journal é falso.
- Comando com `sudo` no Pi: pedir a senha ao Thomaz na hora; nunca gravá-la
  em arquivo ou comando.
