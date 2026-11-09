#!/usr/bin/env bash
# Prepara somente o plano de encerramento; não apaga recursos ou dados.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAYER="${1:-platform}"
echo "Este comando gera um plano de destruição para revisão. Não executa exclusões."
echo "Antes de encerrar: preserve as evidências, revise NLB e volumes Retain e siga docs/RUNBOOK.md."
exec "${ROOT}/scripts/tf-plan.sh" "$LAYER" --destroy
