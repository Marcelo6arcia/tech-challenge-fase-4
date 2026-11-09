#!/usr/bin/env bash
# Provisionamento por etapa com plano salvo, identidade explícita e confirmação.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-plan}"
LAYER="${2:-infra}"
[[ "$LAYER" == infra || "$LAYER" == platform ]] || { echo "Camada inválida."; exit 2; }
if [[ "$ACTION" == plan ]]; then exec "${ROOT}/scripts/tf-plan.sh" "$LAYER"; fi
[[ "$ACTION" == apply ]] || { echo "Uso: bootstrap.sh plan|apply infra|platform"; exit 2; }
EXPECTED_ACCOUNT="${FIAP_ACCOUNT_ID:?Defina FIAP_ACCOUNT_ID.}"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
export AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap AWS_REGION=us-east-1 AWS_PAGER=""
ACTUAL_ACCOUNT="$(aws --profile fiap sts get-caller-identity --query Account --output text)"
[[ "$ACTUAL_ACCOUNT" == "$EXPECTED_ACCOUNT" ]] || { echo "Conta divergente."; exit 1; }
PLAN="${ROOT}/.runs/plans/${LAYER}.tfplan"
[[ -f "$PLAN" && -f "${PLAN}.account" && -f "${PLAN}.sha256" ]] || { echo "Gere e revise o plano primeiro."; exit 1; }
[[ "$(cat "${PLAN}.account")" == "$ACTUAL_ACCOUNT" ]] || { echo "Plano de outra conta."; exit 1; }
shasum -a 256 -c "${PLAN}.sha256"
printf 'Aplicar o plano revisado de %s na conta %s? Isso pode gerar cobrança.\n' "$LAYER" "$ACTUAL_ACCOUNT"
read -r -p "Digite APLICAR ${ACTUAL_ACCOUNT}: " CONFIRM
[[ "$CONFIRM" == "APLICAR ${ACTUAL_ACCOUNT}" ]] || { echo "Cancelado."; exit 0; }
terraform -chdir="${ROOT}/terraform/envs/dev/${LAYER}" apply -input=false -lock-timeout=5m "$PLAN"
echo "Etapa aplicada. Valide os recursos antes de avançar para a próxima camada."
