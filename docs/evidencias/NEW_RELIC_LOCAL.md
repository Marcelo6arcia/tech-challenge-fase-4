# New Relic — evidência de traces gerados localmente

> **Ingestão, raiz real e correlação SQS confirmadas no New Relic. NÃO LIBERADO PARA GRAVAÇÃO.** Esta execução usou Docker local e o SaaS New Relic; não foi realizada no EKS e não iniciou a janela AWS de 72 horas. Service Map, ensaio de incidentes e evidências finais permanecem pendentes.

## Execução registrada

| Campo | Valor |
|---|---|
| Identificador do teste | `20261110T012419-2948dca6` |
| Intervalo UTC | 10/11/2026, 01:24:19–01:24:21 |
| Intervalo em Brasília (UTC−3) | 09/11/2026, 22:24:19–22:24:21 |
| Origem | Stack Docker local do ToggleMaster |
| Destino consultado | Conta acadêmica New Relic `8717927` |
| Trace consultado | `b583e7e34a2f89e565f324a612133305` |
| Código da correção | `7c399ced7032dc7adfa62a78c28024a7db1e20f4` |

O [relatório sanitizado do smoke](NEW_RELIC_ROOT_SMOKE.json) confirma localmente os cinco serviços, 17 spans, raiz real, vínculo SQS, evento DynamoDB e os três sinais na stack Docker. O escopo desse JSON permanece local. As consultas NRQL registradas abaixo são a evidência adicional da ingestão no SaaS.

O código também passou em Go com race detector/vet/gofmt, nos seis testes Python do fluxo e nos dois workflows remotos afetados. Os [resultados do CI](CI_BOOTSTRAP.md) são uma verificação independente, com outro trace e sem envio ao SaaS. Após as conferências, a stack local foi encerrada preservando volumes e evidências.

## Resultado da consulta NRQL

Consulta executada na conta indicada, enquanto o teste estava dentro da janela de uma hora:

```sql
FROM Span
SELECT count(*), uniqueCount(id),
       filter(count(*), WHERE parent.id IS NULL) AS 'root_spans'
WHERE trace.id = 'b583e7e34a2f89e565f324a612133305'
FACET service.name
SINCE 1 hour ago
LIMIT MAX
```

| `service.name` | `count(*)` | `uniqueCount(id)` | `parent.id IS NULL` |
|---|---:|---:|---:|
| `evaluation-service` | 6 | 6 | 1 |
| `auth-service` | 4 | 4 | 0 |
| `analytics-service` | 3 | 3 | 0 |
| `targeting-service` | 2 | 2 | 0 |
| `flag-service` | 2 | 2 | 0 |
| **Total dos cinco serviços** | **17** | **17** | **1** |

A consulta confirmou dados dos cinco serviços no mesmo `trace.id`, 17 IDs únicos e exatamente um span sem pai, em evaluation. Para revisitar a evidência depois, selecionar um intervalo que contenha os horários UTC registrados; `SINCE 1 hour ago` é uma janela móvel.

O New Relic armazena spans OTLP como eventos `Span` e mapeia `trace_id` para `trace.id`, `span_id` para `id` e `parent_span_id` para `parent.id`. Esses são os campos usados nesta conferência. [Documentação oficial do mapeamento OTLP](https://docs.newrelic.com/docs/opentelemetry/best-practices/opentelemetry-best-practices-traces/).

## Raiz real e correlação entre produtor e consumidor SQS

No trace acima, a consulta dos spans mostrou:

| Serviço | Papel | `name` | `id` | `parent.id` |
|---|---|---|---|---|
| `evaluation-service` | Raiz HTTP server | `GET /evaluate` | `74dd305db042ffe3` | `NULL` |
| `evaluation-service` | Produtor | `feature-flag-events send` | `21966eff07c79c2c` | `74dd305db042ffe3` |
| `analytics-service` | Consumidor | `feature-flag-events process` | `1d3dea3726c9c2a4` | `21966eff07c79c2c` |

Uma consulta NRQL específica confirmou esses três spans no SaaS. O span `GET /evaluate` é do tipo server e não tem pai. Produtor e consumidor possuem `messaging.system = aws_sqs` e `messaging.destination.name = feature-flag-events`. O `parent.id` do produtor aponta para a raiz HTTP, e o do consumidor corresponde exatamente ao `id` do produtor. Isso confirma a continuidade do contexto desde a raiz até analytics na execução local, inclusive na passagem assíncrona pela fila. Não comprova uma execução no serviço SQS da AWS.

## Entidades observadas e limite de acesso

Na lista de entidades APM foram encontrados cinco serviços com provider OpenTelemetry: `auth-service`, `evaluation-service`, `flag-service`, `targeting-service` e `analytics-service`. Isso confirma seu reconhecimento pelo New Relic, mas não atesta as relações exibidas no Service Map.

Ao abrir o detalhe de evaluation, a sessão Basic exibiu restrição de acesso Full. Nenhum upgrade foi ativado. O detalhe APM e o Service Map ainda precisam ser conferidos em uma sessão Full, a confirmar com Vinicius; o papel Admin não comprova esse tipo de acesso.

## Histórico da correção da raiz

O teste anterior `20261110T011425-f34c9bd6`, às 01:14 UTC, confirmou no SaaS 17 spans e a correlação SQS, mas foi reprovado para a conferência da raiz: usava um pai sintético de cliente não exportado. A execução principal acima substitui essa prova e confirma a raiz real. No teste anterior, as primeiras consultas retornaram zero e os spans apareceram após aproximadamente quatro minutos; esse intervalo não estabelece SLA nem prazo geral de indexação. Os contadores de 30 spans por exporter pertenciam somente ao ensaio anterior e não são usados para quantificar o novo trace.

## Limitações e verificações pendentes

- **Detalhe APM e Service Map:** não conferidos devido à restrição da sessão Basic. A lista de cinco entidades e as consultas NRQL não substituem a inspeção visual do mapa.
- **EKS e AWS:** este teste não valida deploy, operação da stack no cluster ou integrações com os recursos AWS provisionados. A janela autorizada de 72 horas não foi iniciada por esta execução.
- **Demais sinais:** este registro atesta traces no New Relic. Não constitui evidência de métricas e logs ingeridos nesse SaaS.
- **Aceitação final:** permanecem pendentes o ensaio no EKS, o Service Map dos cinco serviços, alerta real, incidente no gerenciador, ChatOps, Self-Healing automático com recuperação funcional e os prints finais para relatório e vídeo.

O resultado aprovado aqui é a chegada de spans de cinco serviços ao APM comercial, com raiz HTTP real e correlação do produtor com o consumidor SQS. A liberação para gravação exige concluir as verificações pendentes acima.
