# New Relic — prova local na conta própria

> **Ingestão, raiz real e vínculo SQS confirmados por NRQL; waterfall do trace e Service Map dos cinco serviços conferidos na interface da conta própria.** Os arquivos de captura ainda não foram salvos. **NÃO LIBERADO PARA GRAVAÇÃO.** A origem é Docker/LocalStack; esta execução não comprova o ambiente EKS nem inicia a janela AWS de 72 horas.

## Execução registrada

| Campo | Valor |
|---|---|
| Identificador do teste | `20261110T020854-c83b67ed` |
| Intervalo UTC | 10/11/2026, 02:08:54–02:09:00 |
| Intervalo em Brasília (UTC−3) | 09/11/2026, 23:08:54–23:09:00 |
| Origem | Stack Docker/LocalStack do ToggleMaster, projeto Compose `fiap4` |
| Caminho dos traces | Cinco aplicações → Collector central → New Relic US |
| Destino consultado | Conta própria New Relic `8718919` |
| Trace consultado | `9089a13d6ec55e445e59dc738b0d6a16` |
| Código da raiz real | `7c399ced7032dc7adfa62a78c28024a7db1e20f4` |

O [relatório sanitizado do smoke](NEW_RELIC_CONTA_PROPRIA_SMOKE.json) registra sucesso local nos cinco serviços, 17 spans, raiz real, vínculo produtor/consumidor, persistência no DynamoDB local, métricas Prometheus e logs Loki. Foram omitidos os identificadores sintéticos de usuário, flag e evento; os IDs de correlação do trace foram preservados. O campo `scope` do JSON mantém seu alcance local: a prova da ingestão no SaaS são as consultas NRQL abaixo.

A [evidência anterior](NEW_RELIC_LOCAL.md), da conta `8717927`, permanece como registro histórico separado. Seus trace IDs e resultados não são atribuídos à conta própria. Os [testes do CI](CI_BOOTSTRAP.md) também são uma execução independente, sem envio ao New Relic.

## Ingestão consultada na conta própria

A consulta executada na conta `8718919`, com o teste dentro da janela de 30 minutos, confirmou:

```sql
FROM Span
SELECT count(*), uniqueCount(id)
WHERE trace.id = '9089a13d6ec55e445e59dc738b0d6a16'
FACET service.name
SINCE 30 minutes ago
LIMIT MAX
```

| `service.name` | `count(*)` | `uniqueCount(id)` |
|---|---:|---:|
| `evaluation-service` | 6 | 6 |
| `auth-service` | 4 | 4 |
| `analytics-service` | 3 | 3 |
| `targeting-service` | 2 | 2 |
| `flag-service` | 2 | 2 |
| **Total dos cinco serviços** | **17** | **17** |

Os cinco serviços estão no mesmo `trace.id`, com 17 IDs de span distintos. Para revisar depois, selecionar um intervalo que contenha os horários UTC registrados; as cláusulas `SINCE` abaixo usam janelas móveis. Na ingestão OTLP do New Relic, o identificador de span é `id`, o pai é `parent.id` e o trace é `trace.id`. [Mapeamento oficial](https://docs.newrelic.com/docs/opentelemetry/best-practices/opentelemetry-best-practices-traces/).

## Raiz e passagem assíncrona confirmadas no SaaS

A segunda consulta retornou quatro spans: uma única raiz sem pai e três operações SQS.

```sql
FROM Span
SELECT id, parent.id, name, span.kind, duration.ms,
       messaging.system, messaging.destination.name, service.name
WHERE trace.id = '9089a13d6ec55e445e59dc738b0d6a16'
  AND (parent.id IS NULL OR messaging.system = 'aws_sqs')
SINCE 1 hour ago
LIMIT MAX
```

| Serviço | `name` | `span.kind` | `id` | `parent.id` | Duração (ms) |
|---|---|---|---|---|---:|
| `evaluation-service` | `GET /evaluate` | `server` | `e7d133e536b0746b` | `NULL` | 13,748 |
| `evaluation-service` | `feature-flag-events send` | `producer` | `4eba139bd899b217` | `e7d133e536b0746b` | 8,352 |
| `analytics-service` | `feature-flag-events process` | `consumer` | `5c259ef50d626442` | `4eba139bd899b217` | 63,092 |
| `analytics-service` | `feature-flag-events acknowledge` | `client` | `f625d84189a8c63e` | `5c259ef50d626442` | 1,943 |

As três operações de mensageria apresentam `messaging.system = aws_sqs` e `messaging.destination.name = feature-flag-events`. O produtor é filho da raiz HTTP, o consumidor é filho do produtor e o acknowledge é filho do consumidor. Isso comprova a continuidade do contexto até analytics na conta própria. O consumidor assíncrono pode continuar após a resposta HTTP; as durações representam spans diferentes, não parcelas a somar.

O teste usa a API compatível do LocalStack. A presença de `aws_sqs` e do span DynamoDB não comprova execução em recursos provisionados na AWS.

## Conferências visuais

| Prova | Estado desta evidência | Resultado e próximo passo |
|---|---|---|
| Detalhe do trace no APM | **Conferido na interface** | Trace correto, 17 spans, zero erros e trecho SQS/analytics/DynamoDB observados. Ainda falta salvar a captura para a entrega. |
| Service Map dos cinco serviços | **Conferido na interface** | Cinco nós e relações observados conforme procedimento abaixo. Ainda falta salvar a captura para a entrega. |

### Waterfall de uma requisição

O caminho **APM → evaluation-service → Distributed tracing → grupo GET /evaluate → execução de 02:08:54 UTC** abriu o trace `9089a13d6ec55e445e59dc738b0d6a16`. A interface mostrou **17 spans, zero erros e duração total de 86,09 ms**.

Usando **Expand all**, **Maximize** e a rolagem do waterfall, foram conferidos o envio SQS de aproximadamente **8,35 ms**, o processamento por `analytics-service` de **63,09 ms**, a operação **DynamoDB PutItem de 60,79 ms** e o acknowledge de **1,94 ms**. Os IDs e vínculos entre produtor e consumidor foram confirmados também pela consulta NRQL registrada acima.

A interface apresentou o consumidor com o prefixo **OtherTransaction/consumer/unknown**, associado a `feature-flag-events process`. Esse é o rótulo exibido pelo New Relic; o `name` original do span foi confirmado como `feature-flag-events process` na consulta NRQL, com `service.name = analytics-service`.

O detalhe indicou **oito entidades**: os cinco microsserviços e as dependências Redis, PostgreSQL e DynamoDB. Isso não significa oito microsserviços. A conferência visual foi concluída na sessão autenticada; **nenhum arquivo de imagem do waterfall foi salvo**. A captura legível para o relatório e o vídeo permanece pendente.

### Mapa de dependências dos serviços

Na conta `8718919`, o caminho **APM → evaluation-service → Maps** abriu o mapa de relacionamentos sem solicitar upgrade. Inicialmente, a tela mostrava quatro nós. Ao selecionar `flag-service` e usar o controle de expandir relacionamentos, identificado pelo ícone de duas setas verticais, a tela adicionou `auth-service` e passou a indicar **Showing 5 nodes**. Os relacionamentos de `targeting-service` também foram expandidos.

A conferência visual identificou os cinco serviços e estas relações:

| Origem | Destino |
|---|---|
| `evaluation-service` | `analytics-service` |
| `evaluation-service` | `targeting-service` |
| `evaluation-service` | `flag-service` |
| `flag-service` | `auth-service` |
| `targeting-service` | `auth-service` |

Essa observação ocorreu no mapa de relacionamentos da entidade, separado do detalhe de um trace. A interface foi inspecionada durante a sessão autenticada, mas **nenhum arquivo PNG dessa tela foi salvo**. O registro acima descreve o resultado observado e o procedimento para repeti-lo; não é um arquivo de captura já disponível para o PDF. A consulta ao mapa exige sessão e permissão na conta. Antes da entrega, salvar uma imagem legível do mapa e repetir a conferência com a telemetria do ensaio EKS.

O trace representa uma requisição específica. O Service Map representa dependências entre entidades. Uma tabela NRQL, a lista de entidades ou o mapa exibido dentro do detalhe de um único trace não são automaticamente prova do Service Map solicitado. A conferência deve identificar a tela utilizada e as relações efetivamente observadas. [Service Map no New Relic](https://docs.newrelic.com/docs/new-relic-solutions/new-relic-one/ui-data/service-maps/service-maps/).

Na matriz da entrega, R09 exige o trace distribuído e seu print no PDF; R10 exige o Service Map dos cinco microsserviços. Ambos devem ser demonstrados no vídeo. O print separado do mapa é um reforço recomendado, além dos quatro prints obrigatórios.

## Limites desta execução

- O resultado confirmado é ingestão de traces e correlação por NRQL no novo destino, além da conferência visual do waterfall e do Service Map com cinco serviços. Os arquivos de captura das duas telas permanecem pendentes.
- Este registro não atesta ingestão de métricas e logs no New Relic. Esses sinais foram verificados no Prometheus e no Loki da stack local.
- Não houve comprovação EKS nesta execução. Repetir o fluxo no ambiente final, com dados atuais e evidências próprias.
- Alerta real, incidente no gerenciador, ChatOps, Self-Healing automático e recuperação funcional no cluster continuam fora do alcance desta prova.
- Não atribuir à conta própria dados antigos nem considerar a preparação local como liberação para a gravação final.
