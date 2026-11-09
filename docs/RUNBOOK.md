# Runbook operacional — ToggleMaster fase 4

> **NÃO LIBERADO PARA GRAVAÇÃO.** Estado em 09/11/2026: integração Docker local validada; EKS, APM comercial, PagerDuty, ChatOps e Self-Healing no cluster ainda precisam de prova. Os comandos de cluster abaixo são procedimentos para o ambiente acadêmico quando ele estiver provisionado e validado; não foram executados como parte da escrita deste documento.

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

1. Confirmar que a conta New Relic e a chave de ingestão foram realmente preparadas. A existência de um Secret com nome correto não comprova validade da chave.
2. Conferir conta/região e endpoint configurados no exporter `otlphttp/newrelic`, sem exibir o header `api-key`. Endpoint atual do código: `https://otlp.nr-data.net:4318`; alinhar à região da conta antes de implantar.
3. Observar logs do gateway: 401/403 sugerem autenticação/permissão; timeout pode indicar saída de rede/DNS. Não imprimir configurações resolvidas com credenciais.
4. Fazer uma requisição nova com `demo.py trace`, localizar o ID atual no APM e usar janela de tempo coerente.
5. Conferir `service.name` dos cinco serviços e spans HTTP client/server, produtor SQS, consumidor analytics e DynamoDB.

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
