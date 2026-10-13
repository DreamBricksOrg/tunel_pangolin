#!/usr/bin/env bash
# tunel - expoe portas locais em subdominios HTTPS usando o Pangolin (Linux/macOS).
#
# Uso:
#   tunel 8001 dbaudiosync              -> https://dbaudiosync.<dominio>  ->  localhost:8001
#   tunel 8001                          -> https://p8001.<dominio>        ->  localhost:8001
#   tunel 8001:dbaudiosync 3000:teste   (varios tuneis ao mesmo tempo)
#   tunel 8001 dbaudiosync --dry-run    (so mostra o blueprint gerado)
#
# Credenciais ficam em tunel.config.json (mesma pasta do script).
set -euo pipefail

DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
CFG="$DIR/tunel.config.json"
[[ -f "$CFG" ]] || { echo "Nao achei $CFG" >&2; exit 1; }

cfg() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$CFG" "$1"; }
ID=$(cfg id); SECRET=$(cfg secret); ENDPOINT=$(cfg endpoint); DOMAIN=$(cfg domain); BIN=$(cfg pangolin)

DRY=0; ARGS=()
for a in "$@"; do [[ "$a" == "--dry-run" ]] && DRY=1 || ARGS+=("$a"); done
[[ ${#ARGS[@]} -gt 0 ]] || { sed -n '4,8p' "$0" | sed 's/^# \?//'; exit 1; }

# "8001 nome" vira "8001:nome"
if [[ ${#ARGS[@]} -eq 2 && "${ARGS[0]}" =~ ^[0-9]+$ && "${ARGS[1]}" != *:* && ! "${ARGS[1]}" =~ ^[0-9]+$ ]]; then
  ARGS=("${ARGS[0]}:${ARGS[1]}")
fi

YAML="public-resources:"$'\n'
LINHAS=()
for s in "${ARGS[@]}"; do
  porta="${s%%:*}"
  [[ "$porta" =~ ^[0-9]+$ ]] || { echo "Porta invalida: '$s'. Use porta ou porta:nome" >&2; exit 1; }
  sub="p$porta"; [[ "$s" == *:* && -n "${s#*:}" ]] && sub="${s#*:}"
  sub="$(printf '%s' "$sub" | tr '[:upper:]' '[:lower:]')"
  [[ "$sub" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || { echo "Nome invalido: '$sub' (use letras, numeros e hifen)" >&2; exit 1; }
  YAML+="  tunel-$sub:
    name: tunel $sub
    mode: http
    full-domain: $sub.$DOMAIN
    enabled: true
    auth:
      sso-enabled: false
    targets:
      - hostname: localhost
        port: $porta
        method: http

"
  LINHAS+=("$(printf '  %-45s -> http://localhost:%s' "https://$sub.$DOMAIN" "$porta")")
done

BP="${TMPDIR:-/tmp}/tunel-blueprint-$USER.yaml"
printf '%s' "$YAML" > "$BP"

if [[ $DRY -eq 1 ]]; then cat "$BP"; exit 0; fi

echo
for l in "${LINHAS[@]}"; do printf '\033[32m%s\033[0m\n' "$l"; done
printf '\n  Ctrl+C para encerrar.\n\n'

exec "$BIN" up site --id "$ID" --secret "$SECRET" --endpoint "$ENDPOINT" --blueprint-file "$BP"
