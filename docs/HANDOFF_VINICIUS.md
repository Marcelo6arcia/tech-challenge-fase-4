# Handoff para Vinicius — demonstração da fase 4

> **NÃO LIBERADO PARA GRAVAÇÃO.** Em 09/11/2026 (BRT), integração local, CI remoto e ingestão de traces no New Relic estão confirmados. Ainda faltam o ensaio no EKS, a conferência visual do detalhe APM/Service Map, PagerDuty, ChatOps e Self-Healing automático no cluster. A janela AWS de 72 horas não iniciou. Este documento prepara a passagem; não declara o ambiente pronto.

Meta: Marcelo entregar o ambiente ensaiado e o pacote completo até **12/11/2026**, para Vinicius gravar o vídeo. Entrega acadêmica informada: **15/11/2026**. O vídeo deve ter **até 25 minutos**; o roteiro abaixo ocupa 23 minutos e reserva dois minutos de margem. O horário de fechamento do portal ainda deve ser confirmado.

## Responsabilidades

| Responsável | Entrega |
|---|---|
| Marcelo | Preparar EKS, IaC, GitOps, imagens e integrações; organizar acessos acadêmicos; executar o ensaio completo; corrigir falhas; entregar links, comandos, evidências e versões demonstradas. |
| Vinicius | Gravar a demonstração do ambiente já liberado, conferir áudio/legibilidade/tempo e revisar o vídeo completo. Não assumir implementação, provisionamento ou correções de última hora. |

Se um requisito não funcionar durante o ensaio, volta para Marcelo antes da gravação. Se falhar durante a gravação, registre o problema e interrompa essa prova; não substitua a automação por ação manual nem narre resultado que não apareceu.

## Estado confirmado e pendências

| Item | Situação em 09/11/2026 (BRT) | Limite da evidência |
|---|---|---|
| Cinco serviços em Docker | Smoke local aprovado; cinco health checks 200 e avaliação `true`. | Não comprova implantação no EKS. |
| Fluxo distribuído | NRQL confirmou 17 spans dos cinco serviços no mesmo trace, raiz HTTP real e consumidor analytics ligado ao produtor SQS. | Origem Docker local; Service Map ainda não conferido. |
| Evento de negócio | Evento correspondente localizado no DynamoDB do LocalStack. | Não comprova DynamoDB/SQS da AWS. |
| Três sinais | Métricas no Prometheus, logs OTLP correlacionados e nove linhas correspondentes no Loki para o trace do smoke. | Integração Docker local. |
| Testes e build | 36 testes Python dos serviços; testes Go com race detector, vet e lint; 15 testes do runbook; builds Docker aprovados. | Testes locais; Kubernetes e integrações externas não são simulados como prova final. |
| CI remoto | Base inicial aprovada; correção da raiz em `7c399ce` também aprovada no pipeline evaluation e na integração, com 17 spans dos cinco serviços e raiz real. [Execuções e commits](evidencias/CI_BOOTSTRAP.md). | ECR, promoção GitOps e plan/apply cloud ainda desabilitados. A integração do CI não envia dados ao New Relic nem comprova implantação. |
| Configurações da stack | Helm/Kustomize, configurações Collector/Loki, Promtool e provisionamento Grafana conferidos localmente. | Renderização/configuração válida não significa instalação no cluster. |
| Segurança local | SCA dos seis serviços e scan das seis imagens passaram no filtro CRITICAL com correção disponível, após corrigir quatro imagens Python. Smoke repetido com as novas imagens passou. | Gate local; não substitui os pipelines remotos ou scan das futuras imagens publicadas. |
| AWS acadêmica | Inventário não encontrou EKS, RDS ou ECR; bucket de backend existente. Prévia infra: 115 criações, zero alterações e zero exclusões. | Consulta/plan; nenhum apply. Plataforma ainda depende do cluster. |
| New Relic | Conta ativa, ingestão consultada via NRQL e cinco entidades OpenTelemetry encontradas. | A sessão Basic bloqueou detalhe/Service Map; aguarda uma sessão Full, a confirmar com Vinicius. Benefício Students não confirmado. |
| PagerDuty | A tentativa de SUBMIT retornou erro genérico; nenhuma conta ativa confirmada. | Restrição de e-mail gratuito é hipótese documentada, não causa comprovada. Incidente externo ainda não demonstrado. |
| ChatOps/Self-Healing | Código e configuração preparados, sem prova integrada no cluster. | Não liberados para gravação. |

Evidência local: [relatório sanitizado do smoke](evidencias/LOCAL_SMOKE.json), execução de 09/11/2026 às 17:48 UTC, `passed=true`. Trace de referência: `0d935bf18337d21a6c85486083e49949`. Esse arquivo é evidência local e não deve ser apresentado como um trace já disponível no New Relic. A correção e os IDs das imagens estão na [evidência de segurança](evidencias/SECURITY_LOCAL.md).

A execução de 09/11 às 22:24 BRT confirmou localmente 17 spans e raiz real, também conferidos no SaaS por NRQL, incluindo o vínculo SQS: [evidência New Relic local](evidencias/NEW_RELIC_LOCAL.md) e [smoke correspondente](evidencias/NEW_RELIC_ROOT_SMOKE.json). Essas provas não substituem o ensaio no EKS nem a conferência visual do APM.

## Condições para Marcelo liberar a gravação

Todas as condições abaixo precisam de evidência recente do ambiente que será gravado:

- [ ] Conta/profile/contexto acadêmico conferidos; EKS provisionado por Terraform após revisão do plano.
- [ ] Imagens da fase 4 publicadas e cinco serviços disponíveis; pipelines DevSecOps e GitOps preservados.
- [ ] ArgoCD mostra as aplicações esperadas sincronizadas e saudáveis, com a stack de observabilidade.
- [ ] Dashboard customizado mostra recursos do cluster, requisições dos serviços e logs atuais; Loki recebe logs dos contêineres do cluster.
- [ ] Collector roteia métricas, logs e traces; não há falha persistente de exportação.
- [ ] Requisição de demonstração encontrada no New Relic pelo `trace_id`, com percurso HTTP, SQS, analytics e DynamoDB.
- [ ] Service Map real mostra os cinco microsserviços e suas dependências.
- [ ] Falha controlada provoca alerta `AuthHigh5xx` em **Firing**, incidente no PagerDuty e notificação detalhada no canal acadêmico.
- [ ] O mesmo alerta aciona o runbook, que solicita e acompanha o rollout de `auth-service` automaticamente.
- [ ] Novas requisições válidas, queda da taxa de erros e normalização do alerta comprovam recuperação funcional.
- [ ] Quatro prints obrigatórios capturados e legíveis; links de código/vídeo e identificação dos participantes preparados.
- [ ] Ensaio completo cronometrado, sem credenciais visíveis; acessos conferidos na máquina de Vinicius.

Marcelo registra a liberação com data/hora, commit das aplicações, commit GitOps, imagens, cluster/contexto e resultado do ensaio. Enquanto houver item aberto, mantenha o aviso do topo.

## Pacote que Vinicius deve receber até 12/11

1. Links dos repositórios e commits exatos demonstrados, diagrama final e versão deste roteiro.
2. Links/telas de Grafana, ArgoCD, New Relic, PagerDuty e canal acadêmico; acesso individual já testado, sem chaves ou webhooks dentro do documento.
3. [Comandos de demonstração](COMANDOS_DEMO.md) revisados e terminais preparados. O script lê somente as chaves necessárias em memória.
4. Identificadores do ensaio: trace, incidente, episódio do runbook e horários, vinculados à mesma falha.
5. Quatro prints obrigatórios e evidências complementares, com dados legíveis e sem credenciais.
6. Relatório PDF preparado para acrescentar o link do vídeo e a identificação final dos participantes.

Este arquivo não envia uma mensagem ao Vinicius nem concede acesso automaticamente.

## Contas acadêmicas a preparar

O New Relic já está ativo, com login individual e ingestão dos cinco serviços confirmados. O detalhe APM/Service Map exibiu restrição Full na sessão Basic; confirmar com Vinicius a disponibilidade de uma sessão Full para conferir essas telas. O papel Admin e o tipo Basic/Full são controles distintos: ser Admin não confirma acesso Full. No PagerDuty, o titular tentou SUBMIT e recebeu erro genérico; conta ativa e integração permanecem pendentes. Não repetir etapas de confirmação de e-mail/senha do New Relic já concluídas. Usar os dados de cadastro combinados fora do documento, sem publicar e-mails pessoais ou senhas.

1. **Conta New Relic US:** usar a conta acadêmica existente, que recebeu a telemetria local; não criar outra organização. A [região da conta](https://docs.newrelic.com/docs/accounts/accounts-billing/account-setup/choose-your-data-center/) precisa continuar alinhada ao endpoint do Collector na implantação.
2. **Benefício Students:** a [documentação oficial](https://docs.newrelic.com/docs/accounts/accounts-billing/account-setup/student-program/), consultada em 09/11/2026, anuncia 500 GB/mês e três usuários completos por dois anos, mas informa que o **self-service está indisponível** e orienta solicitar provisionamento ao suporte. O fluxo OAuth GitHub ainda aparece na página, porém está condicionado à retomada do self-service; não presumir ativação automática. A [abertura de caso depende do plano de suporte](https://docs.newrelic.com/docs/new-relic-solutions/solve-common-issues/find-help-get-support/), portanto conferir a opção na conta. A solicitação só estará concluída quando o benefício estiver visivelmente aplicado.
3. **Comprovação estudantil:** para o caminho [GitHub Education](https://docs.github.com/en/education/about-github-education/github-education-for-students/apply-to-github-education-as-a-student), confirmar conta pessoal e matrícula atual, com documento aceito, como carteira estudantil com data, histórico ou declaração. O GitHub pode exigir e-mail acadêmico conforme a instituição; Gmail sozinho não garante elegibilidade.
4. **Acesso para gravar:** o [Free Tier comum](https://newrelic.com/pricing/free-tier) tem 100 GB/mês e somente um usuário completo. A restrição prevista para [usuários Basic](https://docs.newrelic.com/docs/accounts/accounts-billing/new-relic-one-user-management/user-type/) foi observada ao abrir o detalhe APM. Usar logins individuais, confirmar com Vinicius se sua sessão é Full e testar o detalhe e o Service Map antes do handoff. Nenhum upgrade foi ativado.
5. **PagerDuty:** a tentativa no [cadastro Developer](https://docs.pagerduty.com/developer/signup) falhou com erro genérico no SUBMIT. A [Developer Account gratuita](https://docs.pagerduty.com/developer/developer-account-faq) prevê três usuários completos e dois stakeholders, mas a conta da dupla não está confirmada. A [política de e-mail para Free/trial](https://www.pagerduty.com/faq/email-guidelines/) restringe domínios gratuitos, e há [relato oficial semelhante no Developer](https://community.pagerduty.com/ask-a-product-question-2/reqesting-a-developer-account-gives-error-774); isso sustenta uma hipótese, sem provar a causa do erro observado. Solicitar diagnóstico ao suporte antes de novas tentativas, sem recorrer a contas de outros projetos. A prova exige abertura automática de incidente; o ChatOps é enviado pelo Grafana ao canal acadêmico.
6. **Discord:** preparar o canal acadêmico da dupla e seu webhook. A integração precisa receber a mensagem do alerta real durante o ensaio.
7. **Segredos:** guardar license key, integration key e webhook somente nos segredos correspondentes do ambiente; conferir referências ExternalSecret/Grafana/Collector. Nenhum valor pertence ao Git, às capturas ou ao roteiro.

**Prazo:** não há prazo garantido identificado para a aprovação GitHub ou o provisionamento Students pelo suporte. Os [5–10 dias úteis publicados](https://newrelic.com/students-verification) referem-se aos outros parceiros, não ao caminho GitHub. A meta de 12/11 depende dessas validações e do ensaio; criar a conta Free não comprova o benefício educacional nem libera a gravação.

Com a conta gratuita já ativa, o titular pode adaptar a solicitação abaixo para o suporte do benefício Students. É um rascunho; nenhuma mensagem foi enviada:

> Olá! Estamos preparando um projeto acadêmico da FIAP e queremos solicitar o New Relic for Students. A documentação informa que a ativação self-service está indisponível. Poderiam confirmar os requisitos, as informações da conta necessárias e o canal adequado para comprovar a condição de estudante? Ainda precisamos confirmar a elegibilidade pelo GitHub Education. Obrigado!

## Preparação da sessão de gravação

Na raiz de `togglemaster/`, seguir primeiro a seção 2 de [COMANDOS_DEMO.md](COMANDOS_DEMO.md). O alias do contexto é `togglemaster-fase4`, com autenticação do profile `fiap`. A conta esperada precisa estar preenchida. O Ingress é acessado em loopback pelo port-forward acadêmico; os comandos abaixo presumem esse túnel já aberto:

```bash
export FIAP_BASE_URL='http://127.0.0.1:18080'
export FIAP_ACCOUNT_ID='ID-DE-12-DIGITOS-DA-CONTA-FIAP'

python3 scripts/demo.py status --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

Não grave a preparação dos acessos ou telas de Secret. Abra antes as abas de ArgoCD, dashboard/Explore/alerta Grafana, APM, PagerDuty e ChatOps. Mantenha um terminal para carga, outro para os comandos e outro para logs/pods do runbook, conforme [RUNBOOK.md](RUNBOOK.md).

## Roteiro de 23 minutos

| Tempo | Ação e explicação | Prova que deve aparecer |
|---|---|---|
| 00:00–02:00 | Apresentar ToggleMaster, cinco serviços e a falha silenciosa que motivou a fase 4. Mostrar o diagrama HTTP → cache/serviços → SQS → analytics. | Arquitetura real e objetivo da observabilidade/resposta automática. |
| 02:00–05:00 | Mostrar IaC, pipelines DevSecOps e ArgoCD com a nova stack. Não executar um provisionamento inteiro no vídeo. | EKS existente, recursos declarados, aplicações sincronizadas/saudáveis e imagens/commits do ensaio. |
| 05:00–09:00 | Abrir dashboard customizado e Loki Explore. Explicar Collector central, agente de logs dos nós e destinos Prometheus/Loki/APM. | Recursos do cluster, taxas HTTP, logs recentes e dados dos serviços. Capturar print do dashboard. |
| 09:00–13:00 | Executar `prepare` e `trace`; localizar o ID no New Relic. Abrir spans detalhados e Service Map. | Cinco serviços, vínculos HTTP e salto assíncrono SQS/analytics; print do trace. |
| 13:00–20:00 | Iniciar carga, ativar falha em outro terminal e acompanhar a cadeia real de incidente. | Firing → PagerDuty → ChatOps → execução do runbook → pods novos → requisições recuperadas. Capturar prints de ChatOps e execução. |
| 20:00–22:00 | Explicar proteção contra repetição, cooldown, alvo/RBAC limitados e compatibilidade com GitOps. Mostrar a distinção entre rollout e recuperação funcional. | Logs do episódio e estado normalizado; nenhum restart manual como prova. |
| 22:00–23:00 | Mostrar os links e evidências que compõem a entrega e encerrar. | Relatório PDF, código e vídeo identificados; nada pendente apresentado como concluído. |

### Requisição para o APM, entre 09:00 e 13:00

```bash
python3 scripts/demo.py prepare --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"

python3 scripts/demo.py trace --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

Use o `trace_id` desta execução. O script cria outra flag quando necessário para evitar cache hit; alterar somente o usuário não elimina o cache da flag. HTTP 200 não comprova ingestão no APM ou Service Map. Se o mapa não mostrar analytics, interrompa a liberação e investigue a propagação SQS.

### Incidente, entre 13:00 e 20:00

Terminal A, mantendo tráfego suficiente para o alerta:

```bash
python3 scripts/demo.py load --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID" --seconds 300 --rps 5
```

Terminal B, somente após o ensaio completo e com a carga em execução:

```bash
python3 scripts/demo.py fault --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

A falha é local à memória do processo auth que recebeu a chamada. `/validate` retorna 503 nesse processo, enquanto `/health` permanece 200. Com mais de uma réplica podem coexistir respostas 200 e 503. O script não reinicia pods. O alerta usa taxa de erros maior que 5%, janela de um minuto, mínimo de 20 requisições e condição sustentada por 30 segundos. A duração observada depende do tráfego, dos intervalos de coleta e do rollout; ensaiar essa espera antes da gravação.

Depois da ação automática:

```bash
python3 scripts/demo.py status --mode cluster \
  --base-url "$FIAP_BASE_URL" --context togglemaster-fase4 \
  --aws-account-id "$FIAP_ACCOUNT_ID"
```

Mostrar as respostas válidas e a queda dos erros, além dos pods novos. O log `rollout_completed` sozinho não comprova recuperação funcional. Se precisar de recuperação manual, fazer fora da prova, registrar como intervenção humana e ensaiar um novo episódio real após resolver a causa.

## Capturas e revisão final

| Evidência | Conteúdo mínimo |
|---|---|
| **Print obrigatório: dashboard Grafana** | Dashboard customizado legível, recursos do cluster, taxas HTTP e painel de logs atuais. |
| **Print obrigatório: trace no APM** | ID/horário e spans do percurso distribuído; não usar o JSON do smoke como substituto. |
| **Print obrigatório: ChatOps** | Mensagem real com identificação do alerta/incidente, serviço e horário, sem URL secreta do webhook. |
| **Print obrigatório: Self-Healing** | Logs do episódio com decisão aceita, alvo, solicitação e conclusão do rollout; relacionar à falha mostrada. |
| Complementares | Service Map dos cinco serviços, Firing, incidente PagerDuty, ArgoCD, pods antes/depois e requisições recuperadas. |

Vinicius revisa o vídeo inteiro: até 25 minutos, áudio compreensível, textos legíveis e nenhuma credencial exibida. Marcelo confere no PDF os nomes, RMs, usernames, links de repositórios e vídeo, os quatro prints e a justificativa da arquitetura OTel e das escolhas New Relic/PagerDuty. Confirmar acesso aos links pelo avaliador antes da submissão.

## Metas de preparação

| Data | Meta | Responsável |
|---|---|---|
| 10/11/2026 | Infraestrutura acadêmica e integrações; primeira prova no APM e nos canais de incidente. | Marcelo |
| 11/11/2026 | Ensaio ponta a ponta, correções e capturas; cronometrar o cenário automático. | Marcelo |
| 12/11/2026 | Pacote e ambiente liberados para Vinicius após os critérios de aceite. | Marcelo entrega; Vinicius confere acessos e gravação. |
| 15/11/2026 | Submissão acadêmica, dentro do horário do portal a confirmar. | Equipe |

São metas, não marcos concluídos. A fidelidade ao enunciado depende de mostrar os requisitos operando, não somente configurados.
