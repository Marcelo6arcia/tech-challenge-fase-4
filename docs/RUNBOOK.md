# Runbook operacional — ToggleMaster fase 4

> **NÃO LIBERADO PARA GRAVAÇÃO.** Estado em 09/11/2026 (BRT): integração Docker, CI remoto e ingestão de traces no New Relic confirmados. EKS, detalhe APM/Service Map, PagerDuty, ChatOps e Self-Healing no cluster ainda precisam de prova; a janela AWS de 72 horas não iniciou. Os comandos de cluster abaixo são procedimentos para o ambiente acadêmico quando ele estiver provisionado e validado; não foram executados como parte da escrita deste documento.

Escopo: diagnosticar observabilidade, alerta e automação da fase 4. Marcelo prepara e opera o ambiente; Vinicius recebe a sessão ensaiada para gravar, sem assumir implementação. Meta de passagem: 12/11/2026; entrega acadêmica: 15/11/2026.

## 1. Identificar o ambiente antes de operar

Usar somente a conta acadêmica esperada, profile AWS `fiap` e contexto Kubernetes `togglemaster-fase4`. Seguir a validação descrita em [COMANDOS_DEMO.md](COMANDOS_DEMO.md): o contexto deve referenciar o ARN EKS dessa conta e usar `aws eks get-token` com o profile correto. Não prosseguir se a identidade divergir. Abrir um terminal sem credenciais estáticas herdadas de outras contas.

```bash
aws --profile fiap sts get-caller-identity

AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 get nodes

AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n observability get pods,svc,pvc

AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n argocd get applications
```

Resultados esperados: identidade acadêmica correta, nós prontos, pods/volumes da stack disponíveis e aplicações ArgoCD coerentes com os commits pretendidos. Ausência de cluster não é falha do Collector: concluir o provisionamento por IaC primeiro, após plano revisado. Este runbook não autoriza um apply nem contém um comando de criação de infraestrutura.

Na consulta feita pela sessão em 09/11, não havia EKS/RDS/ECR e o bucket de backend existia. A prévia de infraestrutura produziu 115 criações, zero alterações e zero exclusões; nenhum apply ocorreu. Conferir novamente e atualizar o plano antes de qualquer mudança.

## 2. Acesso às telas por port-forward

Em terminais separados, depois da conferência de identidade/contexto:

```bash
AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n ingress-nginx \
  port-forward svc/ingress-nginx-controller 18080:80
```

```bash
AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n observability \
  port-forward svc/grafana 3000:80
```

```bash
AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n argocd \
  port-forward svc/argocd-server 18081:80
```

Abrir Grafana em `http://localhost:3000` e ArgoCD em `http://localhost:18081`, com os acessos acadêmicos previamente preparados. O Ingress fica em `http://127.0.0.1:18080`. Manter as portas apenas em loopback. Se a porta estiver ocupada, liberar o túnel antigo ou preparar outra porta antes do ensaio e ajustar a URL correspondente.

Não imprimir Secrets, `.env.local`, tokens, chaves APM ou URLs de webhooks. Os scripts de demonstração leem as chaves necessárias em memória. Os logs de auditoria do runbook registram eventos, episódio e alvo; não registram Authorization, token, payload completo nem texto sensível da exceção. Conferir o conteúdo da tela antes de capturar evidências.

## 3. Verificar aplicação e gerar uma referência rastreável

Na raiz `togglemaster/`, preencher a conta esperada e usar os comandos existentes:

```bash
export FIAP_BASE_URL='http://127.0.0.1:18080'
export FIAP_ACCOUNT_ID='ID-DE-12-DIGITOS-DA-CONTA-FIAP'

python3 scripts/demo.py status --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"

python3 scripts/demo.py prepare --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"

python3 scripts/demo.py trace --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

Guardar o `trace_id`, a flag sintética e o horário da execução. `status` consulta cinco health checks e dez respostas de `/auth/validate`; `/health` 200 não exclui a falha de demonstração. `trace` usa flag nova quando necessário: cache hit evita flag/targeting/auth, e trocar apenas `user_id` não invalida esse cache.

## 4. Métricas ou logs ausentes no Grafana

**Primeiro separar ausência de tráfego, ausência de dados e erro de visualização.** No Grafana Explore, consultar Prometheus:

```promql
sum by (service_name) (app_http_requests_total)
```

```promql
sum by (service_name, http_response_status_code) (
  rate(app_http_requests_total{http_route!="/health"}[1m])
)
```

Para o consumidor, consultar também `app_messages_processed_total` e `app_messages_errors_total`; o trabalho principal de analytics ocorre na fila, não em uma rota de negócio HTTP.

No Explore com Loki, substituir o ID pelo trace da execução atual:

```logql
{service_name=~"auth-service|flag-service|targeting-service|evaluation-service|analytics-service"} | trace_id="TRACE_ID_DA_EXECUCAO"
```

1. Confirmar faixa de tempo e datasource selecionado; aguardar os intervalos de exportação/coleta.
2. Gerar tráfego válido com os comandos da seção 3; health checks sozinhos não provam métricas de negócio.
3. Conferir pods, Service e Endpoints dos componentes, sem consultar valores de Secret.

```bash
AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n observability \
  get svc,endpoints otel-gateway prometheus loki

AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n observability \
  logs deployment/otel-gateway --since=10m --tail=100

AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n observability \
  logs daemonset/otel-agent --all-pods=true --since=10m --tail=50
```

O caminho declarado é aplicação OTLP → gateway → Prometheus/Loki/APM. O agente coleta logs de contêineres e métricas dos nós, enviando ao gateway. Aplicações Go/Python exportam logs OTLP e marcam seu espelho stdout com `otel_exported=true`; o agente exclui esse espelho para evitar duplicação. Se faltarem logs de componentes do cluster, conferir agente em todos os nós, montagem/checkpoints e pipeline de logs; não tratar os logs OTLP dos cinco serviços como prova de todos os contêineres.

Erros de conexão apontam para Service/DNS/rede; rejeição de configuração aponta para valores/chart; volume pendente aponta para StorageClass/CSI/permissões. Corrigir manifests/valores no GitOps e observar a reconciliação. Não desativar o pipeline ou inventar dados para preencher o painel.

## 5. Trace ou Service Map ausente no APM

Estado conhecido: a conta New Relic está ativa; a [execução Docker local](evidencias/NEW_RELIC_LOCAL.md) confirmou no SaaS 17 spans dos cinco serviços, raiz HTTP real e a relação produtor/consumidor SQS. O detalhe APM/Service Map foi bloqueado pela restrição Full na sessão Basic. Conferir essas telas em uma sessão Full, a confirmar com Vinicius, continua pendente.

1. Usar a conta acadêmica existente e separar falha de ingestão de restrição de acesso à interface. Um Secret com nome correto não comprova validade da chave, e entidades listadas não comprovam o Service Map. Benefício Students e tipo/permissões do usuário são verificações distintas, descritas no [handoff](HANDOFF_VINICIUS.md#contas-acadêmicas-a-preparar).
2. Conferir conta/região e endpoint configurados no exporter `otlphttp/newrelic`, sem exibir o header `api-key`. Endpoint atual do código: `https://otlp.nr-data.net:4318`; alinhar à região da conta antes de implantar.
3. Observar logs do gateway: 401/403 sugerem autenticação/permissão; timeout pode indicar saída de rede/DNS. Não imprimir configurações resolvidas com credenciais.
4. Fazer uma requisição nova com `demo.py trace`, consultar o `trace.id` atual via NRQL e usar conta e janela de tempo coerentes. A primeira consulta pode retornar zero antes de os dados ficarem pesquisáveis. No teste registrado, os spans apareceram após aproximadamente quatro minutos; isso não estabelece SLA nem prazo geral de indexação.
5. Se o exporter reportar envio, mas os spans continuarem ausentes, consultar `NrIntegrationError` no mesmo intervalo. A validação assíncrona pode detectar problemas depois de uma resposta de sucesso do endpoint OTLP. [Troubleshooting oficial do New Relic](https://docs.newrelic.com/docs/opentelemetry/best-practices/opentelemetry-otlp-troubleshooting/).
6. Conferir `service.name` dos cinco serviços, spans HTTP client/server, produtor SQS, consumidor analytics e DynamoDB. Verificar `id`/`parent.id` e exatamente um span raiz sem pai; a execução de referência confirmou essa estrutura no SaaS. Repetir a verificação para o trace do ensaio no EKS.

Consulta de diagnóstico, na conta acadêmica, ajustando o intervalo ao teste:

```sql
FROM NrIntegrationError
SELECT timestamp, message, newRelicFeature
SINCE 1 hour ago
LIMIT 100
```

Essa consulta é um procedimento, não um resultado já executado nesta evidência. Correlacionar os eventos pelo horário e origem; não atribuir qualquer erro da conta automaticamente ao trace do teste. Revisar o conteúdo antes de capturar a tela. Contadores de envio e fila vazia do Collector ajudam no diagnóstico, mas a consulta dos spans no destino é a confirmação da ingestão.

Se evaluation aparecer sozinho, verificar cache e instrumentação dos clientes. Se analytics faltar, verificar recebimento da fila e os atributos W3C `traceparent`/`tracestate` como MessageAttributes String, extraídos pelo consumidor. O produtor mantém o contexto após encerrar a resposta HTTP. Se o trace estiver completo e o mapa ainda incompleto, investigar suporte/agrupamento do APM; não criar dependência falsa nem substituir APM comercial por visualização local.

## 6. Fila ou analytics sem evento

No dashboard, comparar processamento e erros de analytics. Conferir se evaluation registrou `evaluation.event.sent` ou `evaluation.event.send.failed`, e se o consumidor registrou processamento/persistência correlacionados.

```bash
AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n togglemaster \
  logs deployment/evaluation-service --all-pods=true --since=10m --tail=100

AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n togglemaster \
  logs deployment/analytics-service --all-pods=true --since=10m --tail=100
```

Conferir nomes/URLs da fila, tabela, região, ServiceAccount/IRSA e permissões específicas, sem mostrar tokens. O endpoint `AWS_ENDPOINT_URL` do LocalStack é exclusivo do ambiente local; não deve substituir o endpoint real no cluster. Falha de envio SQS pode ocorrer depois do HTTP 200 de evaluation; sucesso HTTP não comprova evento persistido. Não purgar fila nem DLQ como diagnóstico. Preservar a mensagem/evidência e corrigir a causa antes de tentar novo cenário sintético.

## 7. Alerta não entra em Firing

Regra declarada: `AuthHigh5xx`, serviço `auth-service`, namespace `togglemaster`, rota `/validate`; taxa 5xx maior que 5%, pelo menos 20 requisições em um minuto e condição sustentada por 30 segundos. Avaliação configurada a cada 10 segundos. A regra completa está em `observability/values/grafana.yaml` do repositório GitOps da fase 4; não editar limiares na interface só para obter uma captura.

1. Confirmar que a regra não está pausada e datasource está saudável. `NoData`/`Error` não são a prova do incidente desejado.
2. Iniciar `load` e observar respostas antes de ativar a falha.
3. Ativar `fault` somente quando PagerDuty, ChatOps e runbook estiverem configurados e o cenário autorizado para ensaio.

```bash
python3 scripts/demo.py load --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID" --seconds 300 --rps 5
```

Em outro terminal:

```bash
python3 scripts/demo.py fault --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

`fault` exige `DEMO_FAULT_ENABLED=true` e autenticação master, lida pelo script. Ativa apenas a memória do processo que recebeu a chamada; com duas réplicas, parte das respostas pode continuar 200. `/health` fica saudável para que a liveness não substitua o runbook. Manter a carga durante a janela e a recuperação. Se o comando retorna 404, conferir habilitação/rota; 403 aponta para autenticação. Não revelar a chave para diagnosticar.

## 8. Firing sem PagerDuty ou ChatOps

Pendência atual: o SUBMIT do cadastro PagerDuty retornou erro genérico, sem conta ativa confirmada. A restrição a e-mail gratuito é hipótese apoiada na documentação, não diagnóstico fechado; seguir a conferência de acesso/suporte descrita no [handoff](HANDOFF_VINICIUS.md#contas-acadêmicas-a-preparar) antes do ensaio integrado.

Verificar no Grafana o contact point `togglemaster-incident`, os três receivers e a política de notificação. Confirmar na interface o resultado da entrega e, nas ferramentas externas, conta, serviço de incidente e canal acadêmico corretos. A integração deve estar configurada com credenciais acadêmicas, não de outros projetos.

O webhook do runbook é um receiver separado das notificações PagerDuty/Discord. A entrega para um receiver não comprova a entrega para os demais. Teste de contact point pode validar conectividade, mas não substitui a prova de alerta real abrindo incidente e acionando a mitigação. Após corrigir, repetir o ensaio completo com um novo episódio, respeitando cooldown e o estado do alerta.

## 9. Webhook ou Self-Healing não executa

```bash
AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n observability \
  get deployment/incident-responder service/incident-responder \
  persistentvolumeclaim/incident-responder-state

AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n observability \
  logs deployment/incident-responder --since=15m --timestamps=true --tail=150

AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n togglemaster \
  get role incident-responder-auth

AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n togglemaster \
  get rolebinding incident-responder-auth
```

O responder aceita somente `POST /webhook`, Bearer válido e labels `alertname=AuthHigh5xx`, `namespace=togglemaster`, `service=auth-service`. A NetworkPolicy permite entrada do Grafana no mesmo namespace. Não expor o receiver publicamente para contornar uma falha de rede.

| Resultado observado | Interpretação e ação |
|---|---|
| HTTP 401 | Token do receiver não corresponde ao token do runbook. Conferir referências e sincronização dos Secrets sem mostrar valores. |
| HTTP 400/413 | Formato, timestamp ou tamanho inválido. Conferir contrato do webhook; não reenviar payload manual para fabricar prova. |
| HTTP 503 | Falha interna antes de aceitar. Consultar auditoria, disponibilidade do PVC e permissões de escrita. |
| `accepted` | Episódio persistido e ação agendada; ainda não significa rollout concluído. |
| `duplicate` | Episódio já registrado, inclusive resolução recebida antes de firing atrasado. Não apagar SQLite/PVC para forçar repetição. |
| `cooldown` | Última ação aceita há menos de 600 segundos. Aguardar e preparar episódio novo após recuperação e normalização. |
| `ignored_target` | Labels não correspondem ao único alvo permitido. Conferir regra/roteamento; não ampliar a lista de alvos para a demonstração. |
| `ignored_stale` | Início mais de 30 minutos atrás ou mais de 60 segundos no futuro. Conferir relógios e episódio atual. |
| `resolved_recorded` / `ignored_not_firing` | Resolução ou evento sem ação de mitigação. A resolução é persistida para bloquear replay tardio. |
| `restart_requested` | PATCH aceito pela API; conferir geração e pods. |
| `runbook_failed`, HTTP 403 | RBAC/ServiceAccount inadequado. Permissão esperada: somente `get`/`patch` no Deployment `togglemaster/auth-service`. |
| `runbook_failed`, HTTP 409 | Deployment mudou entre leitura e PATCH. Proteção por `resourceVersion` evitou sobreposição; investigar a concorrência. |
| `runbook_failed`, `TimeoutError` | Rollout não terminou em 180 segundos; examinar pods/eventos e capacidade. |
| `runbook_failed`, `ValueError` | Alvo pausado/zerado ou rollout substituído por outra geração/anotação. Conferir deployment e GitOps; não alegar que a mitigação concluiu. |
| `rollout_completed` | Réplicas da geração/anotação esperadas disponíveis. Ainda verificar respostas e métricas de negócio. |

O estado fica no SQLite do PVC; há uma tentativa por episódio, persistida antes de executar. O pod do runbook usa uma réplica e estratégia `Recreate`. Uma interrupção depois de registrar `accepted` pode deixar a tentativa incompleta; não há retry automático. Investigar e recuperar operacionalmente, mantendo a evidência da falha.

## 10. Acompanhar rollout e confirmar recuperação

```bash
AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n togglemaster \
  get pods -l app.kubernetes.io/name=auth-service -w
```

Em outro terminal:

```bash
AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n togglemaster \
  rollout status deployment/auth-service --timeout=180s

python3 scripts/demo.py status --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

`rollout status` apenas acompanha; não inicia restart. O runbook altera `spec.template.metadata.annotations["fiap.dev/incident-restart"]`, preservada pelo `ignoreDifferences` específico e `RespectIgnoreDifferences=true` no ArgoCD. Se outra geração ou anotação substituir o episódio, o runbook não registra sucesso dessa ação.

Confirmar: requisições `/validate` voltaram a 200, taxa 5xx caiu com tráfego ainda presente, alerta normalizou e incidente/notificação de resolução chegaram quando configurados. Registrar horário, episódio e imagens usadas. Um pod novo ou health 200 isolado não comprova recuperação funcional.

Se a automação falhar, qualquer restart manual é **recuperação operacional fora da prova**. Registrar a intervenção e corrigir o fluxo antes de repetir o cenário real. Não usar terminal manual ou webhook enviado à mão como se fossem Self-Healing disparado pelo alerta.

## 11. Evidências e passagem

Preservar o JSON local e os resultados de testes como validação de desenvolvimento. Para a entrega, capturar dashboard Grafana, trace no APM, notificação ChatOps e execução do Self-Healing; mostrar também Service Map, Firing, incidente e recuperação funcional. Conferir que horários/IDs pertencem ao mesmo ensaio.

Metas: 10/11 infraestrutura/integrações; 11/11 ensaio e correções; 12/11 pacote liberado para Vinicius. A condição de liberação e o roteiro de 23 minutos estão em [HANDOFF_VINICIUS.md](HANDOFF_VINICIUS.md). Não marcar a tarefa pronta antes das provas externas.

## 12. Encerramento da janela autorizada de 72 horas

**Procedimento preparado; não executado.** Na preparação desta seção, a janela
AWS ainda não começou. Marcelo autorizou a infraestrutura acadêmica por até
72 horas, incluindo seu encerramento dentro desse limite. Registrar `T0` no
início do primeiro apply que criar recursos e calcular o limite `T0 + 72h`.
Começar o encerramento **pelo menos três horas antes do limite**, reservando tempo
para finalizers, desanexação de discos, exclusão de RDS e rede.

A revisão do plano atual é obrigatória em cada camada. A confirmação
`DESTRUIR <conta>` do script serve para conferir o alvo; não exige pedir novamente
uma autorização de encerramento que já foi dada. Uma ampliação da janela ou
inclusão de recursos de outro projeto não faz parte dessa autorização.

### 12.1. Identidade, evidências e inventário anterior à exclusão

Concluir as capturas e copiar as evidências necessárias para fora dos PVCs antes
de desmontar a stack. Parar carga/fault, congelar alterações GitOps e impedir
jobs de provisionamento concorrentes. Conferir no GitHub Actions que não há
plan/apply/deploy em execução; durante o encerramento, desabilitar o workflow
Terraform do repositório da fase 4:

```bash
gh workflow disable terraform.yml --repo Marcelo6arcia/tech-challenge-fase-4
```

Na raiz `togglemaster/`, em terminal dedicado:

```bash
export FIAP_APP_DIR="$PWD"
export FIAP_ACCOUNT_ID='ID-DE-12-DIGITOS-DA-CONTA-FIAP'
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
unset TF_DATA_DIR
export AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap AWS_REGION=us-east-1 AWS_PAGER=''
umask 077
mkdir -p .runs/encerramento

aws --profile fiap sts get-caller-identity
kubectl --context togglemaster-fase4 config view --minify
kubectl --context togglemaster-fase4 get nodes
```

Comparar o Account retornado com `FIAP_ACCOUNT_ID`; conferir que o contexto aponta
para o ARN EKS dessa conta e autentica pelo profile `fiap`, como na seção 1.
Interromper se houver divergência. Não usar `--raw` no kubeconfig, nem registrar
Secrets ou o conteúdo dos states. Conferir os backends exclusivos
`togglemaster/fase4/infra.tfstate` e `togglemaster/fase4/platform.tfstate`.

Guardar nomes/IDs anteriores à limpeza, para não depender de objetos já apagados:

```bash
terraform -chdir=terraform/envs/dev/infra state list > .runs/encerramento/infra-state-addresses.txt
terraform -chdir=terraform/envs/dev/platform state list > .runs/encerramento/platform-state-addresses.txt
terraform -chdir=terraform/envs/dev/infra output -raw vpc_id > .runs/encerramento/vpc-id.txt
terraform -chdir=terraform/envs/dev/infra output -raw eks_cluster_name > .runs/encerramento/cluster-name.txt

kubectl --context togglemaster-fase4 -n argocd get applications,applicationsets -o json \
  > .runs/encerramento/argocd-before.json
kubectl --context togglemaster-fase4 -n observability get pvc -o json \
  > .runs/encerramento/pvc-before.json
kubectl --context togglemaster-fase4 get pv \
  -o custom-columns='PV:metadata.name,NAMESPACE:spec.claimRef.namespace,PVC:spec.claimRef.name,CLAIM_UID:spec.claimRef.uid,CLASS:spec.storageClassName,RECLAIM:spec.persistentVolumeReclaimPolicy,DRIVER:spec.csi.driver,VOLUME:spec.csi.volumeHandle' \
  > .runs/encerramento/pv-map-before.txt
kubectl --context togglemaster-fase4 -n ingress-nginx get svc ingress-nginx-controller -o json \
  > .runs/encerramento/ingress-service-before.json
```

Montar uma lista revisada **somente** dos PVCs de `observability` com StorageClass
`gp3-observability`, associando nome/UID do claim, PV e `spec.csi.volumeHandle`.
Os valores atuais pedem Prometheus 10Gi, Loki 10Gi, Grafana 2Gi e responder 1Gi;
confirmar o inventário real, sem deduzir nomes ou IDs apenas pelo tamanho.
Registrar também IDs/ARNs dos recursos AWS da fase 4 presentes no plano/state:
EKS/nodes, três RDS, Redis, tabela, filas/DLQ, seis ECR, IAM, Secrets Manager,
VPC, NAT/EIPs se existirem, logs e discos. `terraform state list` registra
endereços Terraform, não substitui essa lista de IDs.

Identificar o NLB pelo DNS do Service e conferir VPC/tags de propriedade:

```bash
FIAP_NLB_DNS="$(kubectl --context togglemaster-fase4 -n ingress-nginx \
  get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"

aws --profile fiap --region us-east-1 elbv2 describe-load-balancers \
  --query "LoadBalancers[?DNSName=='${FIAP_NLB_DNS}'].[LoadBalancerArn,VpcId,DNSName]" \
  --output json > .runs/encerramento/nlb-before.json
```

O resultado deve identificar exatamente o NLB desse Service e a VPC registrada.
Copiar seu ARN para `FIAP_NLB_ARN` e confirmar as tags antes de usá-lo:

```bash
export FIAP_NLB_ARN='ARN-EXATO-CONFERIDO-NO-INVENTARIO'
aws --profile fiap --region us-east-1 elbv2 describe-tags \
  --resource-arns "$FIAP_NLB_ARN" > .runs/encerramento/nlb-tags-before.json
```

Se o Service não tiver NLB provisionado, registrar essa ausência, conferir que
não ficou um LB parcial da mesma criação e não executar comandos com ARN vazio.

### 12.2. Parar os reconciliadores que poderiam recriar Applications

A Application raiz se chama **`root`**, criada pelo release Terraform
`argocd-apps`. Ela recria as Applications e o ApplicationSet
**`togglemaster-services`**. Remover só as filhas enquanto esses objetos continuam
reconciliando pode fazer os recursos voltarem.

Primeiro, desabilitar o sync automático da raiz e parar apenas o controlador de
ApplicationSets. **Manter `argocd-application-controller` ativo**, pois ele precisa
processar os finalizers das aplicações filhas:

```bash
kubectl --context togglemaster-fase4 -n argocd patch application root --type merge \
  -p '{"spec":{"syncPolicy":{"automated":null}}}'
kubectl --context togglemaster-fase4 -n argocd scale \
  deployment/argocd-applicationset-controller --replicas=0
kubectl --context togglemaster-fase4 -n argocd get deployment argocd-applicationset-controller
kubectl --context togglemaster-fase4 -n argocd get application root \
  -o jsonpath='{.status.operationState.phase}{"\n"}{.metadata.finalizers}{"\n"}'
```

Confirmar zero réplicas ativas do controlador de ApplicationSets e nenhuma
operação da raiz em andamento. Se houver sync ativo, terminar essa operação na
UI/CLI ArgoCD e aguardar sua parada. No código atual, `root` não declara o
finalizer de cascata; confirmada essa condição, removê-la preservando as filhas:

```bash
kubectl --context togglemaster-fase4 -n argocd delete application root \
  --cascade=orphan --wait=true
kubectl --context togglemaster-fase4 -n argocd delete applicationset togglemaster-services \
  --cascade=orphan --wait=true
```

Se `root` tiver recebido o finalizer de cascata em runtime, usar a operação
**não cascata** do ArgoCD, `argocd app delete root --cascade=false`, na sessão
acadêmica já autenticada. `--cascade=orphan` do kubectl sozinho não neutraliza um
finalizer ArgoCD. Essa exceção é exclusiva da raiz: **não remover os finalizers
das filhas**, que são necessários para limpar seus recursos.

Conferir que `root` e o ApplicationSet desapareceram, as filhas continuam
presentes e não são recriadas por outra automação. Não executar Terraform apply
normal nem reativar o workflow durante o encerramento; usar somente os planos
de destruição das etapas abaixo.

### 12.3. Excluir as Applications filhas mantendo ArgoCD/CSI disponíveis

As cinco Applications de negócio e as sete Applications de observabilidade,
além de `platform`, declaram `resources-finalizer.argocd.argoproj.io`. Excluí-las
com seus finalizers permite que o ArgoCD remova os recursos gerenciados. A
foundation fica por último porque contém Namespace e StorageClass.

```bash
kubectl --context togglemaster-fase4 -n argocd delete application \
  auth-service flag-service targeting-service evaluation-service analytics-service \
  platform grafana incident-responder prometheus loki otel-agent otel-gateway \
  --wait=false

kubectl --context togglemaster-fase4 -n argocd wait --for=delete \
  application/auth-service application/flag-service application/targeting-service \
  application/evaluation-service application/analytics-service application/platform \
  application/grafana application/incident-responder application/prometheus \
  application/loki application/otel-agent application/otel-gateway --timeout=900s
```

Confirmar ausência dos workloads desses aplicativos. Se uma Application ficar
em `Terminating`, investigar seus recursos/finalizers e permissões enquanto o
cluster e o ArgoCD ainda existem. Não limpar finalizers à força para aparentar
sucesso e não apagar o cluster antes de resolver a limpeza.

A Application **`platform`** do ArgoCD remove Ingress/ExternalSecrets/bootstrap
da aplicação. Ela **não é** a camada Terraform `platform`, nem é dona do Service
`ingress-nginx-controller`. Esse Service é instalado pelo release Helm do
Terraform; ele e seu NLB serão removidos explicitamente na etapa 12.5, antes
da destruição geral da plataforma.

### 12.4. Encerrar os volumes `Retain` por IDs conferidos

`gp3-observability` usa `reclaimPolicy: Retain`; remover PVC ou Namespace não
remove automaticamente o EBS. Loki também configura retenção dos PVCs do
StatefulSet. Antes de apagar dados, conferir que prints/logs necessários à
entrega já foram preservados fora desses discos.

Para **cada entrada revisada** do mapeamento da etapa 12.1, preencher os nomes e
ID exatos; não alimentar estas variáveis com uma busca ampla seguida de delete:

```bash
export FIAP_PVC='NOME-EXATO-DO-CLAIM-CONFERIDO'
export FIAP_PV='NOME-EXATO-DO-PV-CONFERIDO'
export FIAP_VOLUME_ID='vol-ID-EXATO-CONFERIDO'

kubectl --context togglemaster-fase4 get pv "$FIAP_PV" -o json
aws --profile fiap --region us-east-1 ec2 describe-volumes \
  --volume-ids "$FIAP_VOLUME_ID" \
  --query 'Volumes[].{Id:VolumeId,State:State,Attachments:Attachments,Tags:Tags}'
```

Comparar claim/UID/namespace, driver `ebs.csi.aws.com`, volumeHandle e tags do
volume com o inventário. A aplicação correspondente deve estar removida e nenhum
pod pode usar o claim. Se o PVC ainda existir, removê-lo pelo nome registrado;
aguardar a desanexação pelo CSI, sem usar `--force`:

```bash
kubectl --context togglemaster-fase4 -n observability delete pvc "$FIAP_PVC" \
  --ignore-not-found=true --wait=true --timeout=300s
aws --profile fiap --region us-east-1 ec2 wait volume-available \
  --volume-ids "$FIAP_VOLUME_ID"
```

Reconsultar o volume e confirmar `available` com `Attachments=[]`. Só então
excluir esse EBS identificado e o objeto PV restante:

```bash
aws --profile fiap --region us-east-1 ec2 delete-volume --volume-id "$FIAP_VOLUME_ID"
aws --profile fiap --region us-east-1 ec2 wait volume-deleted --volume-ids "$FIAP_VOLUME_ID"
kubectl --context togglemaster-fase4 delete pv "$FIAP_PV" --ignore-not-found=true
```

Falha/timeout do waiter exige investigação; não equivale a volume removido.
Confirmar a resposta de ausência do ID na consulta final. Não excluir volumes
somente porque estão `available`: podem pertencer a outro projeto. Não criar
snapshots de retenção automaticamente, pois eles mantêm armazenamento cobrado.
Registrar o destino de cada um dos quatro volumes efetivamente encontrados.

Depois de concluir os claims/PVs dessa stack, remover a foundation com seu
finalizer e aguardar a exclusão do Namespace/StorageClass que ela gerencia:

```bash
kubectl --context togglemaster-fase4 -n argocd delete application observability-foundation --wait=false
kubectl --context togglemaster-fase4 -n argocd wait --for=delete \
  application/observability-foundation --timeout=600s
kubectl --context togglemaster-fase4 -n argocd get applications,applicationsets
```

A lista esperada é vazia para o projeto. Qualquer Application de outro projeto
não faz parte da lista de exclusão deste procedimento.

### 12.5. Remover Service/NLB com controladores ativos; depois destruir platform

O Service `ingress-nginx/ingress-nginx-controller` é dono do NLB e pertence ao
release Helm instalado por Terraform. Removê-lo **antes** do destroy geral da
plataforma, mantendo EKS, nodes e os controladores responsáveis pelo LB ativos.
Não depender da ordem de destruição paralela dos releases para a reconciliação
dos finalizers na AWS.

Esta é uma intervenção específica do encerramento autorizado: a raiz/AppSet já
foram retirados e o CI está congelado. Helm/Terraform não têm reconciliação
contínua que recrie esse Service sem uma nova execução. Não fazer apply normal
entre sua remoção e o destroy; o plano posterior refletirá o estado remanescente.

```bash
kubectl --context togglemaster-fase4 -n ingress-nginx delete service ingress-nginx-controller --wait=false
kubectl --context togglemaster-fase4 -n ingress-nginx wait --for=delete \
  service/ingress-nginx-controller --timeout=900s

aws --profile fiap --region us-east-1 elbv2 wait load-balancers-deleted \
  --load-balancer-arns "$FIAP_NLB_ARN"
aws --profile fiap --region us-east-1 elbv2 describe-load-balancers \
  --load-balancer-arns "$FIAP_NLB_ARN"
```

Usar somente o **ARN previamente conferido**. A consulta final deve retornar
`LoadBalancerNotFound`, não AccessDenied ou erro de rede. Se o NLB persistir,
inspecionar Service/finalizers, eventos e o controlador responsável enquanto
eles ainda estiverem disponíveis. Resolver o bloqueio antes de destruir a
plataforma ou EKS/VPC; não retirar finalizers à força. Conferir também target
groups/ENIs ligados ao NLB inventariado. Não remover recursos homônimos nem
fazer exclusão de todos os LBs da conta.

Com o NLB comprovadamente ausente e a limpeza dos volumes concluída, gerar um
plano **novo** de platform. O refresh e a remoção dos releases tratam o Service
que já não existe; não executar um apply de recriação para corrigir esse drift:

```bash
scripts/destroy.sh platform
terraform -chdir=terraform/envs/dev/platform show -no-color \
  "$FIAP_APP_DIR/.runs/plans/platform-destroy.tfplan"
scripts/bootstrap.sh apply-destroy platform
```

O script aplica exatamente esse plano salvo, confere conta/hash e solicita
`DESTRUIR <conta>`. Não trocar por `terraform destroy -auto-approve`. Conferir que
o plano elimina somente a plataforma acadêmica da fase 4. A camada infra deve
continuar ativa até o término bem-sucedido desta etapa.

### 12.6. Destruir infra e registrar o inventário final

Somente depois da plataforma removida, do NLB ausente e dos volumes revisados:

```bash
scripts/destroy.sh infra
terraform -chdir=terraform/envs/dev/infra show -no-color \
  "$FIAP_APP_DIR/.runs/plans/infra-destroy.tfplan"
scripts/bootstrap.sh apply-destroy infra
```

Revisar o plano atual, sem reutilizar um plano produzido antes das etapas
anteriores. Os padrões atuais de laboratório permitem excluir RDS sem snapshot
final e ECR com imagens; guardar previamente as evidências e referências de
imagens/commits necessárias à entrega. Não destruir `terraform/bootstrap`, o
bucket de state compartilhado nem states de fases anteriores.

Ao terminar, registrar horário final e consultar os IDs/ARNs capturados no início:

- Ambos os `terraform state list` da fase 4 devem ficar vazios; guardar a saída.
- Confirmar ausência de EKS/node groups, instâncias EC2 da stack, três RDS,
  ElastiCache, tabela DynamoDB, filas/DLQ, seis ECR e recursos IAM/Secrets Manager
  gerenciados pela fase 4. Registrar estados de exclusão pendente, se houver.
- Confirmar ausência do NLB, target groups/ENIs associados, quatro EBS
  inventariados, NAT Gateways/EIPs da stack quando existentes e VPC/subnets.
- Conferir logs/snapshots/backups e qualquer armazenamento que tenha sido
  explicitamente preservado; anotar o recurso, motivo e custo residual previsto.
  O bucket/state já existente permanece como registro, fora da limpeza da stack.
- Conservar repositórios, vídeo, relatório e evidências. A exclusão da
  infraestrutura não deve apagar os entregáveis acadêmicos.

Usar consultas por IDs/ARNs e tags da fase 4 somente como conferência, nunca uma
varredura que apague automaticamente resultados. `AccessDenied`, timeout ou state
vazio isoladamente não comprovam que a AWS terminou a remoção. Custos podem ter
atraso de atualização; registrar a evidência de exclusão e posteriormente conferir
a cobrança, sem declarar custo zero apenas porque o Terraform terminou.

Atualizar `memories.md` e o registro de encerramento com o que efetivamente foi
removido, pendências e prazo. Se surgir bloqueio, atuar e avisar antes do limite
já autorizado; não deixar recursos ativos por inércia nem tratar uma extensão
além das 72 horas como aprovada.

Referências operacionais: [cascata e finalizers do ArgoCD](https://argo-cd.readthedocs.io/en/stable/user-guide/app_deletion/),
[exclusão de ApplicationSet com órfãos](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Application-Deletion/),
[waiter de volume EBS](https://docs.aws.amazon.com/cli/latest/reference/ec2/wait/volume-deleted.html) e
[waiter de NLB](https://docs.aws.amazon.com/cli/latest/reference/elbv2/wait/load-balancers-deleted.html).
