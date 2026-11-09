#!/usr/bin/env bash
# =============================================================================
# smoke-test.sh — valida a stack ponta a ponta depois do deploy.
#
#   ./scripts/smoke-test.sh                      # descobre o host do Ingress
#   ./scripts/smoke-test.sh http://a1b2c3.elb... # host informado
#
# Percorre o caminho completo: cria uma flag, cria uma regra de segmentação,
# avalia a flag para um usuário e confere se o evento chegou ao DynamoDB.
# =============================================================================
set -euo pipefail

NAMESPACE="${NAMESPACE:-togglemaster}"
REGIAO="${AWS_REGION:-us-east-1}"
PERFIL="${AWS_PROFILE:-}"
PERFIL_ARG=()
[[ -n "$PERFIL" ]] && PERFIL_ARG=(--profile "$PERFIL")

BASE="${1:-}"

if [[ -z "$BASE" ]]; then
  echo ">>> Descobrindo o host do Ingress..."
  HOST=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
  [[ -z "$HOST" ]] && { echo "LoadBalancer ainda sem hostname. Aguarde e tente de novo."; exit 1; }
  BASE="http://${HOST}"
fi

echo ">>> Base: $BASE"

# A chave de serviço vive no Secrets Manager; o Secret do cluster é a cópia
# materializada pelo External Secrets Operator.
CHAVE=$(kubectl -n "$NAMESPACE" get secret evaluation-service-secret \
  -o jsonpath='{.data.SERVICE_API_KEY}' | base64 -d)

AUTH=(-H "Authorization: Bearer ${CHAVE}")
JSON=(-H "Content-Type: application/json")
FLAG="smoke-$(date +%s)"

verificar() {
  local descricao="$1" esperado="$2" obtido="$3"
  if [[ "$obtido" == "$esperado" ]]; then
    echo "  [ok]    $descricao (HTTP $obtido)"
  else
    echo "  [FALHA] $descricao — esperado $esperado, obtido $obtido"
    exit 1
  fi
}

echo
echo ">>> 1. Health checks"
for rota in auth flag targeting evaluation analytics; do
  codigo=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${BASE}/${rota}/health")
  verificar "/${rota}/health" 200 "$codigo"
done

echo
echo ">>> 2. Criando a flag '${FLAG}' com rollout de 100%"
codigo=$(curl -s -o /tmp/flag.json -w '%{http_code}' -X POST "${BASE}/flag/flags" \
  "${AUTH[@]}" "${JSON[@]}" \
  -d "{\"name\":\"${FLAG}\",\"description\":\"smoke test\",\"is_enabled\":true}")
verificar "POST /flag/flags" 201 "$codigo"

echo
echo ">>> 3. Criando a regra de segmentação"
codigo=$(curl -s -o /tmp/rule.json -w '%{http_code}' -X POST "${BASE}/targeting/rules" \
  "${AUTH[@]}" "${JSON[@]}" \
  -d "{\"flag_name\":\"${FLAG}\",\"is_enabled\":true,\"rules\":{\"type\":\"PERCENTAGE\",\"value\":100}}")
verificar "POST /targeting/rules" 201 "$codigo"

echo
echo ">>> 4. Avaliando a flag para 'usuario-smoke'"
RESPOSTA=$(curl -s --max-time 15 "${BASE}/evaluation/evaluate?flag_name=${FLAG}&user_id=usuario-smoke")
echo "  resposta: $RESPOSTA"
echo "$RESPOSTA" | grep -q 'true' \
  && echo "  [ok]    rollout de 100% devolveu true" \
  || { echo "  [FALHA] esperado true na avaliação"; exit 1; }

echo
echo ">>> 5. Conferindo o evento no DynamoDB (aguardando o worker...)"
sleep 12
TABELA=$(kubectl -n "$NAMESPACE" get secret analytics-service-secret \
  -o jsonpath='{.data.AWS_DYNAMODB_TABLE}' | base64 -d)
TOTAL=$(aws dynamodb query \
  --table-name "$TABELA" \
  --index-name flag_name-timestamp-index \
  --key-condition-expression "flag_name = :f" \
  --expression-attribute-values "{\":f\":{\"S\":\"${FLAG}\"}}" \
  --region "$REGIAO" "${PERFIL_ARG[@]}" \
  --query 'Count' --output text)

if [[ "$TOTAL" -ge 1 ]]; then
  echo "  [ok]    $TOTAL evento(s) gravado(s) no DynamoDB"
else
  echo "  [FALHA] nenhum evento encontrado para a flag ${FLAG}"
  exit 1
fi

echo
echo ">>> 6. Estado do cluster"
kubectl -n "$NAMESPACE" get deploy,hpa,pods

echo
echo "Smoke test concluído com sucesso."
