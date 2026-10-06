#!/usr/bin/env bash
# Porta de entrada da esteira no Pi. Instalado UMA vez pelo install.sh em
# ~/.local/bin/homelab-deploy e amarrado a chave de deploy com command=
# forcado no authorized_keys: quem tiver a chave nao ganha shell, so os
# verbos abaixo.
#
#   receive <run> [dry-run]   le o pacote (tar.gz) do stdin, dispara o
#                             apply.sh que veio nele e acompanha o log
#   status <run>              "running" ou o codigo de saida do apply
#   log <run>                 log completo do apply
#
# O pipeline NAO atualiza este arquivo: e a ancora de confianca, e se uma
# versao quebrada chegasse aqui a esteira travaria a si mesma. A logica que
# muda fica no apply.sh, que vem dentro de cada pacote.
#
# O apply roda desacoplado da sessao SSH (setsid + nohup) porque o deploy do
# WireGuard derruba o tunel por onde o runner chegou. O runner reconecta e
# pergunta o status.
set -euo pipefail
umask 077

BASE=/home/admin/docker/.deploy
KEEP_RUNS=10

read -r -a args <<<"${SSH_ORIGINAL_COMMAND:-}"
verb=${args[0]:-}
id=${args[1]:-}
opt=${args[2]:-}

[[ "$id" =~ ^[0-9]+-[0-9]+$ ]] || { echo "uso: receive|status|log <run_id-tentativa>" >&2; exit 2; }
run="$BASE/runs/$id"

case "$verb" in
  receive)
    [[ -z "$opt" || "$opt" == "dry-run" ]] || { echo "opcao invalida" >&2; exit 2; }
    [[ ! -e "$run" ]] || { echo "run $id ja recebido" >&2; exit 2; }
    mkdir -p "$run/bundle"
    tar -xzf - -C "$run/bundle" --no-same-owner
    [[ -f "$run/bundle/repo/deploy/apply.sh" ]] || { echo "pacote sem apply.sh" >&2; exit 2; }
    echo running >"$run/status"
    : >"$run/log"

    # shellcheck disable=SC2016 # expandido pelo bash -c, nao aqui
    setsid nohup bash -c 'bash "$1/bundle/repo/deploy/apply.sh" "$1/bundle" "$2" >"$1/log" 2>&1; echo $? >"$1/status"' \
      _ "$run" "$opt" </dev/null >/dev/null 2>&1 &
    pid=$!

    # Limpa runs antigos (cada um guarda .env em claro)
    find "$BASE/runs" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' |
      sort -rn | tail -n +$((KEEP_RUNS + 1)) | cut -d' ' -f2- | xargs -r rm -rf

    tail -n +1 -f --pid="$pid" "$run/log"
    st=$(cat "$run/status")
    [[ "$st" =~ ^[0-9]+$ ]] || st=1
    exit "$st"
    ;;
  status)
    [[ -f "$run/status" ]] || { echo "run $id desconhecido" >&2; exit 2; }
    cat "$run/status"
    ;;
  log)
    [[ -f "$run/log" ]] || { echo "run $id desconhecido" >&2; exit 2; }
    cat "$run/log"
    ;;
  *)
    echo "verbo invalido" >&2
    exit 2
    ;;
esac
