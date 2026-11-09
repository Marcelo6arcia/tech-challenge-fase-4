#!/usr/bin/env bash
# Gera um plano revisável da fase 4. Não aplica recursos.
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAYER="${1:-infra}"
MODE="${2:-}"
[[ "$LAYER" == infra || "$LAYER" == platform ]] || { echo "Camada inválida: infra ou platform."; exit 2; }
[[ -z "$MODE" || "$MODE" == --destroy ]] || { echo "Opção inválida."; exit 2; }
EXPECTED_ACCOUNT="${FIAP_ACCOUNT_ID:?Defina FIAP_ACCOUNT_ID com a conta acadêmica esperada.}"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
export AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap AWS_REGION=us-east-1 AWS_PAGER=""
ACTUAL_ACCOUNT="$(aws --profile fiap sts get-caller-identity --query Account --output text)"
[[ "$ACTUAL_ACCOUNT" == "$EXPECTED_ACCOUNT" ]] || { echo "Conta divergente; interrompido."; exit 1; }
DIR="${ROOT}/terraform/envs/dev/${LAYER}"
[[ -f "${DIR}/backend.hcl" ]] || { echo "Prepare backend.hcl a partir do exemplo da fase 4."; exit 1; }
grep -Eq "^key[[:space:]]*=[[:space:]]*\"togglemaster/fase4/${LAYER}\.tfstate\"" "${DIR}/backend.hcl" \
  || { echo "Backend não pertence ao prefixo isolado da fase 4."; exit 1; }
mkdir -p "${ROOT}/.runs/plans"
SUFFIX=""
if [[ "$MODE" == --destroy ]]; then SUFFIX="-destroy"; fi
PLAN="${ROOT}/.runs/plans/${LAYER}${SUFFIX}.tfplan"
OPTIONS=(-input=false -lock-timeout=5m "-out=$PLAN")
if [[ "$MODE" == --destroy ]]; then OPTIONS+=(-destroy); fi
terraform -chdir="$DIR" init -reconfigure -input=false -backend-config=backend.hcl
terraform -chdir="$DIR" plan "${OPTIONS[@]}"
printf '%s\n' "$ACTUAL_ACCOUNT" > "${PLAN}.account"
shasum -a 256 "$PLAN" > "${PLAN}.sha256"
printf '\nPlano salvo: %s\nNenhum recurso foi aplicado. Revise o plano antes de continuar.\n' "$PLAN"
