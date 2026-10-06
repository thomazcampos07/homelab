#!/usr/bin/env bash
# Aplica um pacote do deploy no Pi. Chamado pelo receiver.sh, nunca a mao.
#
#   apply.sh <pasta-do-pacote> [dry-run]
#
# O pacote tem:
#   repo/<servico>/...   arquivos versionados (git archive)
#   env/<servico>.env    .env montado com os secrets do GitHub
#   env/clients.list     lista de aparelhos do Pi-hole (opcional)
#   sha                  commit sendo aplicado
#
# Para cada servico que mudou: snapshot -> copia -> pull -> up -> health
# check. Se o health check falhar, volta o snapshot e para ali.
#
# O log deste script aparece no Actions, que e PUBLICO: imprimir so nomes de
# servico, de arquivo e de chave. Nunca valores, nunca o conteudo de .env.
set -euo pipefail
umask 077

B=${1:?uso: apply.sh <pasta-do-pacote> [dry-run]}
MODE=${2:-}
DOCKER=/home/admin/docker
STATE=$DOCKER/.deploy
MANIFEST=$STATE/manifest
# WireGuard por ultimo: o deploy dele derruba o tunel do proprio runner.
SERVICES=(beszel backup pihole wireguard)
HEALTH_TIMEOUT=${HEALTH_TIMEOUT:-90}
STABLE_WAIT=${STABLE_WAIT:-10}

log() { printf '[%s] %s\n' "$(date +%T)" "$*"; }

mkdir -p "$STATE/prev"
touch "$MANIFEST"
exec 9>"$STATE/lock"
flock -w 600 9 || { log "outro deploy segurando o lock ha 10 min"; exit 1; }

log "commit $(cat "$B/sha" 2>/dev/null || echo '?')${MODE:+ ($MODE)}"

# ---------- descobrir o que mudou ----------------------------------------

# Arquivos versionados do servico no pacote, caminhos relativos
bundle_files() { (cd "$B/repo/$1" && find . -type f -printf '%P\n' | sort); }
# O que o deploy anterior instalou (para apagar o que saiu do repo)
previous_files() { awk -F'\t' -v s="$1" '$1 == s { print $2 }' "$MANIFEST" | sort; }

# Mesmo conteudo e mesmo bit de execucao
same_file() {
  [[ -f "$2" ]] && cmp -s "$1" "$2" || return 1
  if [[ -x "$1" ]]; then [[ -x "$2" ]]; else [[ ! -x "$2" ]]; fi
}

# Nomes das chaves cujo valor difere entre dois .env (sem imprimir valores)
env_key_diff() {
  local a=$1 b=$2 k
  { cut -d= -f1 "$a" 2>/dev/null; cut -d= -f1 "$b" 2>/dev/null; } | sort -u | while read -r k; do
    [[ -z "$k" ]] && continue
    if [[ "$(grep -m1 "^$k=" "$a" 2>/dev/null)" != "$(grep -m1 "^$k=" "$b" 2>/dev/null)" ]]; then
      echo "$k"
    fi
  done
}

declare -A REMOVED_FILES CLIENTS RECREATE
pending=()

for svc in "${SERVICES[@]}"; do
  [[ -d "$B/repo/$svc" ]] || { log "$svc: fora do pacote, pulando"; continue; }
  dst=$DOCKER/$svc
  changed=() removed=() recreate=""

  while read -r f; do
    same_file "$B/repo/$svc/$f" "$dst/$f" && continue
    changed+=("$f")
    # Compose nao percebe mudanca em arquivo montado (ex.: unbound.conf).
    # Docs, scripts e o proprio compose nao exigem recriar o container.
    case "$f" in
      docker-compose.yml|*.md|.gitignore|*.sh|*.ps1) ;;
      *) recreate=1 ;;
    esac
  done < <(bundle_files "$svc")

  while read -r f; do
    [[ -n "$f" && -e "$dst/$f" && ! -e "$B/repo/$svc/$f" ]] && removed+=("$f")
  done < <(previous_files "$svc")

  keys=$(env_key_diff "$B/env/$svc.env" "$dst/.env" | tr '\n' ' ')

  clients=""
  if [[ "$svc" == pihole && -f "$B/env/clients.list" ]] && ! cmp -s "$B/env/clients.list" "$dst/clients.list"; then
    clients=1
  fi

  if ((${#changed[@]} == 0 && ${#removed[@]} == 0)) && [[ -z "$keys" && -z "$clients" ]]; then
    log "$svc: sem mudancas"
    continue
  fi

  REMOVED_FILES[$svc]="${removed[*]}"
  CLIENTS[$svc]="$clients"
  RECREATE[$svc]="$recreate"
  pending+=("$svc")

  log "$svc: arquivos [${changed[*]}] removidos [${removed[*]}] chaves do .env [${keys% }]${clients:+ clients.list}${recreate:+ (recriar container)}"
done

if ((${#pending[@]} == 0)); then
  log "nada a aplicar"
  [[ "$MODE" == "dry-run" ]] || cp "$B/sha" "$STATE/deployed-sha"
  exit 0
fi

if [[ "$MODE" == "dry-run" ]]; then
  log "dry-run: nada foi alterado"
  exit 0
fi

# ---------- aplicar ------------------------------------------------------

compose() { docker compose --project-directory "$DOCKER/$1" "${@:2}"; }

snapshot() {
  local svc=$1 dst=$DOCKER/$1 snap=$STATE/prev/$1 f
  rm -rf "$snap" && mkdir -p "$snap/files"
  : >"$snap/new-files"
  { bundle_files "$svc"; previous_files "$svc"; echo .env; echo clients.list; } | sort -u | while read -r f; do
    if [[ -e "$dst/$f" ]]; then
      mkdir -p "$snap/files/$(dirname "$f")"
      cp -p "$dst/$f" "$snap/files/$f"
    else
      echo "$f" >>"$snap/new-files"
    fi
  done
}

rollback() {
  local svc=$1 dst=$DOCKER/$1 snap=$STATE/prev/$1 f
  log "$svc: voltando o snapshot"
  while read -r f; do [[ -n "$f" ]] && rm -f "$dst/$f"; done <"$snap/new-files"
  (cd "$snap/files" && find . -type f -printf '%P\n') | while read -r f; do
    mkdir -p "$dst/$(dirname "$f")"
    cp -p "$snap/files/$f" "$dst/$f"
  done
  if [[ "$svc" != backup ]]; then
    compose "$svc" up -d --remove-orphans ${RECREATE[$svc]:+--force-recreate} || true
  fi
}

install_files() {
  local svc=$1 dst=$DOCKER/$1 f
  tar -C "$B/repo/$svc" -cf - . | tar -C "$dst" -xf - --no-same-owner
  for f in ${REMOVED_FILES[$svc]}; do rm -f "$dst/$f"; done
  install -m 600 "$B/env/$svc.env" "$dst/.env"
  if [[ -n "${CLIENTS[$svc]}" ]]; then
    install -m 600 "$B/env/clients.list" "$dst/clients.list"
  fi
}

update_manifest() {
  local svc=$1 tmp
  tmp=$(mktemp "$STATE/manifest.XXXX")
  awk -F'\t' -v s="$svc" '$1 != s' "$MANIFEST" >"$tmp"
  bundle_files "$svc" | sed "s/^/$svc\t/" >>"$tmp"
  mv "$tmp" "$MANIFEST"
}

# Containers do projeto todos "running" e sem reiniciar sozinhos
containers_stable() {
  local svc=$1 ids before after
  ids=$(compose "$svc" ps -aq)
  [[ -n "$ids" ]] || return 1
  # shellcheck disable=SC2086 # lista de ids
  before=$(docker inspect -f '{{.State.Status}} {{.RestartCount}}' $ids)
  grep -qv '^running ' <<<"$before" && return 1
  sleep "$STABLE_WAIT"
  # shellcheck disable=SC2086
  after=$(docker inspect -f '{{.State.Status}} {{.RestartCount}}' $ids)
  [[ "$before" == "$after" ]]
}

service_ok() {
  case "$1" in
    pihole)    docker exec pihole dig @127.0.0.1 google.com +short +time=5 +tries=2 >/dev/null 2>&1 ;;
    beszel)    curl -fsS -m 5 http://localhost:8090/api/health >/dev/null 2>&1 ;;
    wireguard) docker exec wireguard wg show wg0 >/dev/null 2>&1 ;;
    *)         true ;;
  esac
}

healthy() {
  local svc=$1 deadline=$((SECONDS + HEALTH_TIMEOUT))
  if [[ "$svc" == backup ]]; then
    # Nao ha servico continuo (profile "job"): basta o compose ser valido
    compose "$svc" config -q
    return
  fi
  until containers_stable "$svc" && service_ok "$svc"; do
    ((SECONDS < deadline)) || return 1
    sleep 5
  done
}

# Puxa todas as imagens antes de recriar qualquer coisa: com o Pi-hole fora
# do ar no meio do caminho, um pull depois dele poderia falhar.
for svc in "${pending[@]}"; do
  if ! (cd "$B/repo/$svc" && COMPOSE_PROFILES='*' docker compose --env-file "$B/env/$svc.env" pull --quiet); then
    log "$svc: falha no pull, nada foi alterado"
    exit 1
  fi
done
log "imagens prontas"

for svc in "${pending[@]}"; do
  snapshot "$svc"
  install_files "$svc"

  if [[ "$svc" != backup ]]; then
    if ! compose "$svc" up -d --remove-orphans ${RECREATE[$svc]:+--force-recreate}; then
      log "$svc: falha no up"
      rollback "$svc"
      exit 1
    fi
  fi

  if ! healthy "$svc"; then
    log "$svc: health check falhou em ${HEALTH_TIMEOUT}s"
    rollback "$svc"
    exit 1
  fi

  if [[ -n "${CLIENTS[$svc]}" ]]; then
    # A saida do clients.sh lista MACs: fica fora do log publico
    if (cd "$DOCKER/pihole" && ./clients.sh >/dev/null 2>&1); then
      log "pihole: clientes recadastrados"
    else
      log "pihole: clients.sh falhou (servico segue no ar)"
    fi
  fi

  update_manifest "$svc"
  log "$svc: ok"
done

cp "$B/sha" "$STATE/deployed-sha"
log "deploy concluido"
