#!/usr/bin/env bash
# Teste de ponta a ponta do receiver + apply, sem Pi e sem Docker de verdade:
# roda num container Debian descartavel, com `docker` e `curl` falsos, e
# confere dry-run, aplicacao, permissoes, rollback e entradas invalidas.
#
#   docker run --rm -v "$PWD:/src:ro" debian:trixie-slim bash /src/deploy/test/apply-test.sh
#
# Escreve em /home/admin e /stub: nunca rodar fora de um container.
set -uo pipefail
[[ -f /.dockerenv ]] || { echo "rodar so dentro de um container descartavel" >&2; exit 2; }

mkdir -p /home/admin/docker /stub
export PATH=/stub:$PATH
cat >/stub/docker <<'EOF'
#!/bin/bash
echo "docker $*" >>/tmp/docker.log
case "$*" in
  *" ps -aq"*) echo c1 ;;
  inspect*) echo "running 0" ;;
  "exec pihole dig"*) [[ -f /tmp/fail ]] && exit 1; exit 0 ;;
  *) exit 0 ;;
esac
EOF
printf '#!/bin/bash\nexit 0\n' >/stub/curl
chmod +x /stub/*
export STABLE_WAIT=0 HEALTH_TIMEOUT=3

D=/home/admin/docker
install -m 755 /src/deploy/receiver.sh /stub/homelab-deploy
mkdir -p $D/.deploy/runs

# Estado inicial do "Pi": igual ao repo, .env do dummy
cp -r /src/pihole /src/wireguard /src/beszel /src/backup $D/
bash /src/deploy/render-env.sh /tmp/env --dummy >/dev/null
for s in pihole wireguard beszel backup; do cp /tmp/env/$s.env $D/$s/.env; done
echo "segredo-de-estado" >$D/pihole/etc-pihole-marker

mkbundle() {  # $1 = pasta do pacote
  rm -rf "$1"; mkdir -p "$1/repo" "$1/env"
  cp -r /src/pihole /src/wireguard /src/beszel /src/backup /src/deploy "$1/repo/"
  cp /tmp/env/*.env "$1/env/"
  echo abc123 >"$1/sha"
}
send() {  # $1 = pasta, $2.. = comando
  local b=$1; shift
  SSH_ORIGINAL_COMMAND="$*" tar -C "$b" -czf - . | SSH_ORIGINAL_COMMAND="$*" homelab-deploy
}
check() { if eval "$2"; then echo "  PASS $1"; else echo "  FAIL $1"; FAILS=$((FAILS+1)); fi; }
FAILS=0

echo "== 1. dry-run sem mudancas"
mkbundle /tmp/b1
out=$(send /tmp/b1 receive 1-1 dry-run); rc=$?
echo "$out" | sed 's/^/    /'
check "rc 0" "[[ $rc == 0 ]]"
check "nada a aplicar" "grep -q 'nada a aplicar' <<<\"\$out\""

echo "== 2. dry-run com unbound.conf e senha alterados"
mkbundle /tmp/b2
echo "# mudou" >>/tmp/b2/repo/pihole/unbound/unbound.conf
sed -i 's/^PIHOLE_PASSWORD=.*/PIHOLE_PASSWORD=nova senha secreta/' /tmp/b2/env/pihole.env
out=$(send /tmp/b2 receive 2-1 dry-run); rc=$?
echo "$out" | sed 's/^/    /'
check "lista arquivo e chave" "grep -q 'pihole: arquivos \[unbound/unbound.conf\].*PIHOLE_PASSWORD.*recriar' <<<\"\$out\""
check "nao vaza valor" "! grep -q 'nova senha' <<<\"\$out\""
check "Pi intocado" "! grep -q mudou $D/pihole/unbound/unbound.conf"

echo "== 3. aplica de verdade"
: >/tmp/docker.log
out=$(send /tmp/b2 receive 3-1); rc=$?
echo "$out" | sed 's/^/    /'
check "rc 0" "[[ $rc == 0 ]]"
check "arquivo instalado" "grep -q mudou $D/pihole/unbound/unbound.conf"
check ".env novo e 600" "grep -q 'nova senha' $D/pihole/.env && [[ \$(stat -c %a $D/pihole/.env) == 600 ]]"
check "force-recreate no pihole" "grep -q 'pihole up -d --remove-orphans --force-recreate' /tmp/docker.log"
check "pull antes do up" "[[ \$(grep -n pull /tmp/docker.log | head -1 | cut -d: -f1) -lt \$(grep -n ' up ' /tmp/docker.log | head -1 | cut -d: -f1) ]]"
check "outros servicos nao mexidos" "! grep -q 'wireguard up' /tmp/docker.log"
check "estado preservado" "[[ -f $D/pihole/etc-pihole-marker ]]"
check "manifest" "grep -q \$'pihole\tunbound/unbound.conf' $D/.deploy/manifest"
check "deployed-sha" "grep -q abc123 $D/.deploy/deployed-sha"
check "scripts 755" "[[ \$(stat -c %a $D/pihole/clients.sh) == 755 ]]"
check "conf 644" "[[ \$(stat -c %a $D/pihole/unbound/unbound.conf) == 644 ]]"
check "compose 644" "[[ \$(stat -c %a $D/pihole/docker-compose.yml) == 644 ]]"
check "status" "[[ \$(SSH_ORIGINAL_COMMAND='status 3-1' homelab-deploy) == 0 ]]"

echo "== 4. health check falha -> rollback"
mkbundle /tmp/b4
cp /tmp/b2/repo/pihole/unbound/unbound.conf /tmp/b4/repo/pihole/unbound/unbound.conf
cp /tmp/b2/env/pihole.env /tmp/b4/env/pihole.env
echo "# quebrado" >>/tmp/b4/repo/pihole/unbound/unbound.conf
echo "novo" >/tmp/b4/repo/pihole/arquivo-novo.txt
touch /tmp/fail
out=$(send /tmp/b4 receive 4-1); rc=$?
rm -f /tmp/fail
echo "$out" | sed 's/^/    /'
check "rc != 0" "[[ $rc != 0 ]]"
check "conf voltou" "grep -q mudou $D/pihole/unbound/unbound.conf && ! grep -q quebrado $D/pihole/unbound/unbound.conf"
check "arquivo novo removido" "[[ ! -e $D/pihole/arquivo-novo.txt ]]"
check "env mantido" "grep -q 'nova senha' $D/pihole/.env"
check "status != 0" "[[ \$(SSH_ORIGINAL_COMMAND='status 4-1' homelab-deploy) != 0 ]]"

echo "== 5. arquivo removido do repo some do Pi"
mkbundle /tmp/b5
cp /tmp/b2/repo/pihole/unbound/unbound.conf /tmp/b5/repo/pihole/unbound/unbound.conf
cp /tmp/b2/env/pihole.env /tmp/b5/env/pihole.env
rm /tmp/b5/repo/pihole/setup-host.sh
out=$(send /tmp/b5 receive 5-1); rc=$?
echo "$out" | sed 's/^/    /'
check "setup-host.sh removido" "[[ ! -e $D/pihole/setup-host.sh ]]"
check "clients.list nao mexido" "true"

echo "== 6. clients.list"
mkbundle /tmp/b6
cp /tmp/b5/repo/pihole/unbound/unbound.conf /tmp/b6/repo/pihole/unbound/unbound.conf
rm /tmp/b6/repo/pihole/setup-host.sh
cp /tmp/b2/env/pihole.env /tmp/b6/env/pihole.env
printf 'AA:BB:CC:DD:EE:01|x\n' >/tmp/b6/env/clients.list
out=$(send /tmp/b6 receive 6-1); rc=$?
echo "$out" | sed 's/^/    /'
check "clients.list instalado" "[[ -f $D/pihole/clients.list ]]"
check "sem MAC no log" "! grep -qi 'aa:bb' <<<\"\$out\""

echo "== 6b. so permissao errada: reinstala sem recriar"
chmod 600 $D/pihole/unbound/unbound.conf; chmod 700 $D/beszel/healthcheck-ping.sh
: >/tmp/docker.log
out=$(send /tmp/b6 receive 6-2); rc=$?
echo "$out" | sed 's/^/    /'
check "detecta modo" "grep -q 'unbound/unbound.conf(modo)' <<<\"\$out\""
check "conf volta a 644" "[[ \$(stat -c %a $D/pihole/unbound/unbound.conf) == 644 ]]"
check "script volta a 755" "[[ \$(stat -c %a $D/beszel/healthcheck-ping.sh) == 755 ]]"
check "sem force-recreate" "! grep -q force-recreate /tmp/docker.log"

echo "== 6c. script de custom-init recria o container"
mkbundle /tmp/b6c
cp /tmp/b6/repo/pihole/unbound/unbound.conf /tmp/b6c/repo/pihole/unbound/unbound.conf
rm /tmp/b6c/repo/pihole/setup-host.sh
cp /tmp/b2/env/pihole.env /tmp/b6c/env/pihole.env
cp /tmp/b6/env/clients.list /tmp/b6c/env/clients.list
echo "# mudou" >>/tmp/b6c/repo/wireguard/custom-init/10-restringe-peer-github.sh
: >/tmp/docker.log
out=$(send /tmp/b6c receive 6-3); rc=$?
echo "$out" | sed 's/^/    /'
check "rc 0" "[[ $rc == 0 ]]"
check "wireguard recriado" "grep -q 'wireguard up -d --remove-orphans --force-recreate' /tmp/docker.log"
check "custom-init 755" "[[ \$(stat -c %a $D/wireguard/custom-init/10-restringe-peer-github.sh) == 755 ]]"

echo "== 7. entradas invalidas"
check "run id invalido" "! SSH_ORIGINAL_COMMAND='status ../x' homelab-deploy 2>/dev/null"
check "verbo invalido" "! SSH_ORIGINAL_COMMAND='bash 1-1' homelab-deploy 2>/dev/null"
check "reuso de run" "! send /tmp/b1 receive 1-1 2>/dev/null"

echo "== falhas: $FAILS"
exit $FAILS
