# Comandos para ensaio e demonstração — fase 4

Este roteiro é para Marcelo e Vinicius executarem no ambiente acadêmico. Os
scripts não publicam código, não criam infraestrutura e não reiniciam pods.
As chaves são lidas em memória e não aparecem nos comandos nem nos relatórios.

## 1. Prova local antes do ensaio no cluster

Na raiz `togglemaster/`, com Python 3 e Docker Compose disponíveis:

```bash
python3 scripts/local-env.py
docker compose -p fiap4 --env-file .env.local up -d --build --wait
python3 scripts/local-smoke.py --timeout 120
```

`local-env.py` preserva o arquivo existente e gera credenciais aleatórias quando
necessário. Não cole `.env.local`, saída de `docker compose config` ou arquivos de
Secret no vídeo. Se os volumes já existirem, as credenciais precisam ser as mesmas
usadas para inicializar os bancos; gerar outro `.env.local` não altera bancos existentes.

O smoke executa, em ordem:

1. Confere `/health` dos cinco serviços em `127.0.0.1:18001..18005`.
2. Cria uma flag de nome único e regra `PERCENTAGE=100` usando a chave de serviço.
3. Chama o evaluation com `traceparent` conhecido e exige `result=true`.
4. Consulta o DynamoDB **dentro do LocalStack**, buscando o evento dessa flag/usuário.
5. Lê os arquivos OTLP e exige os cinco serviços no **mesmo trace ligado por parents**.
   Analytics precisa ser um span consumidor filho do produtor SQS.
6. Confere logs correlacionados dos cinco serviços, métricas no Prometheus e os
   mesmos logs no Loki.
7. Grava `.runs/local-smoke-<id>.json` sem chaves, com resultado e evidências resumidas.

O script retorna código 0 somente quando todas as verificações passam. Se falhar,
o JSON conserva as etapas aprovadas e identifica o bloqueio. Ele não ativa falhas,
não sobe containers e não faz chamadas à AWS real. Seu resultado prova a integração
local; **não substitui APM comercial, Service Map, cluster, incidente e Self-Healing**.

As séries HTTP incluem health checks. O dashboard de negócio deve filtrar
`http_route!="/health"`; o processamento de analytics usa
`app_messages_processed_total` e `app_messages_errors_total`.

## 2. Preparar acesso explícito ao cluster acadêmico

O contexto do kubeconfig deve ter o alias **`togglemaster-fase4`**, referenciar o
ARN EKS da conta esperada e usar `aws eks get-token` com o profile **`fiap`**.
A configuração do contexto é uma etapa anterior de provisionamento/acesso.
O script não modifica kubeconfig nem seleciona um contexto global.

O caminho recomendado para o ensaio é acessar o Ingress por **port-forward**.
Primeiro, confirme que o profile `fiap` corresponde à conta acadêmica esperada e
que o contexto tem o ARN correto. Use um terminal sem credenciais estáticas de
outras contas (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN`).

```bash
aws --profile fiap sts get-caller-identity
```

Em um terminal dedicado, mantenha o túnel aberto, usando `fiap` para a autenticação
do kubeconfig:

```bash
AWS_PROFILE=fiap AWS_DEFAULT_PROFILE=fiap \
  kubectl --context togglemaster-fase4 -n ingress-nginx \
  port-forward svc/ingress-nginx-controller 18080:80
```

O HTTP fica restrito ao loopback do computador; o `kubectl` transporta a conexão
pelo canal autenticado e protegido por TLS da API do EKS. Isso não instala um
certificado HTTPS no Ingress. Não exponha o port-forward com `--address 0.0.0.0`.

Em outro terminal, preencha a conta acadêmica e execute a validação:

```bash
export FIAP_BASE_URL='http://127.0.0.1:18080'
export FIAP_ACCOUNT_ID='ID-DE-12-DIGITOS-DA-CONTA-FIAP'

python3 scripts/demo.py status --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

Uma URL pública do Ingress também pode ser usada quando possui **HTTPS com
certificado válido**. O script aceita HTTP somente em `127.0.0.1`, `localhost`
ou `::1`. Não há opção para ignorar a validação TLS. Redirecionamentos HTTP não
são seguidos, mesmo para o mesmo host: informe diretamente a URL final para que
a chave de autenticação não seja reenviada a outro destino.

Antes de qualquer `kubectl`, cada execução valida a identidade com
`aws --profile fiap sts get-caller-identity`. Divergência de conta/contexto/profile
interrompe o comando. Credenciais estáticas herdadas do terminal não substituem
o profile nessa validação. O namespace usado é sempre `togglemaster`.

Leituras de Secret limitadas a:

- `evaluation-service-secret`, campo `SERVICE_API_KEY`, para preparo/carga/validação;
- `auth-service-secret`, campo `MASTER_KEY`, somente para ativar a falha.

`status` verifica os cinco health checks, dez amostras de `/auth/validate` e, no
cluster, nomes/estado/data de criação dos pods auth. A falha controlada mantém
`/health` saudável: isso evita que uma liveness probe substitua a automação pedida.
Com múltiplas réplicas, algumas amostras podem dar 200 enquanto outras dão 503.

## 3. Preparar dados e mostrar o trace no APM

```bash
python3 scripts/demo.py prepare --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"

python3 scripts/demo.py trace --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

`prepare` cria flag única habilitada e regra de 100%. `trace` avalia essa flag e
imprime apenas identificadores de demonstração e resultado. Se a flag já foi
avaliada, cria outra automaticamente: variar somente o usuário não evita o cache
de 30 segundos, pois a chave de cache é a flag.

No APM escolhido, busque o `trace_id` impresso e confira os serviços evaluation,
flag, targeting, auth e analytics, incluindo o salto assíncrono SQS e a gravação
DynamoDB. Mostre também o mapa real de dependências dos cinco serviços. A resposta
HTTP 200, isoladamente, não comprova que o trace ou o Service Map chegaram ao APM.

O estado de demonstração fica em `.runs/demo-cluster.json`, sem credenciais. Não
edite o arquivo durante o ensaio. Cada `prepare` deixa dados sintéticos novos no
ambiente; os scripts não fazem limpeza destrutiva automática.

## 4. Prova de incidente: dois terminais e as telas de evidência

Execute esta parte somente quando alerta, PagerDuty, ChatOps e a automação estiverem
configurados e o cenário acadêmico já tiver sido ensaiado. Ajuste a duração à janela
real do alerta e da automação. O limite do script é 600 segundos e 20 requisições/s.

**Terminal A — manter tráfego de negócio no auth:**

```bash
python3 scripts/demo.py load --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID" --seconds 300 --rps 5
```

A carga chama `/auth/validate` com a chave de serviço, mostra totais a cada dez
segundos e resumo final por status. O envio é sequencial e limitado; lentidão pode
reduzir a taxa real. Ctrl+C encerra a carga e imprime o resumo parcial.

**Terminal B — ativar a falha controlada:**

```bash
python3 scripts/demo.py fault --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

Esse comando faz `POST /auth/admin/demo/fault`, sem body, autenticado com a chave
master. O serviço precisa ter `DEMO_FAULT_ENABLED=true`. A falha vive em memória
no processo que recebe a chamada e faz `/validate` retornar 503. **Não há endpoint
de desligamento**; a mitigação prevista é o restart executado pelo runbook automático.
O script não faz restart manual e não simula a execução da automação.

Mostre, em sequência, as evidências reais:

1. Erros no tráfego e alerta **Firing** no Grafana/APM.
2. Incidente aberto no PagerDuty e notificação detalhada no canal acadêmico.
3. Execução da automação disparada pelo mesmo alerta: alvo, horário, resultado e logs.
4. Mudança dos pods causada pela automação; depois, novas requisições válidas.
5. Como reforço, normalização do alerta e encerramento/resolução do incidente.

Para consultar o resultado depois da ação automática:

```bash
python3 scripts/demo.py status --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

Se a automação falhar, registre o resultado e investigue antes de refazer a prova.
Não apresente um restart manual como Self-Healing automático. O arquivo de carga
não é prova de entrega de ChatOps ou PagerDuty: essas telas precisam ser mostradas.

## 5. Uso local dos comandos auxiliares

```bash
python3 scripts/demo.py prepare
python3 scripts/demo.py trace
python3 scripts/demo.py status
python3 scripts/demo.py load --seconds 30 --rps 2
```

O modo local usa portas fixas de loopback e lê `.env.local`; não aceita opções de
cluster. O comando `fault` também existe localmente, mas o Compose de validação não
inclui o fluxo externo de incidentes/mitigação. O smoke local nunca o ativa.

## 6. Capturas finais

Reserve os quatro prints obrigatórios: dashboard Grafana, trace distribuído no
APM, notificação ChatOps e log/execução do Self-Healing. Confira o vídeo completo
com até 25 minutos, os links do relatório e a correspondência com o commit/versão
realmente demonstrado. Evite capturar chaves, telas de Secret ou URLs de webhooks.
