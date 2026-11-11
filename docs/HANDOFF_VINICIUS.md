# Handoff para Vinicius — demonstração da fase 4

> **NÃO LIBERADO PARA GRAVAÇÃO.** Em 10/11/2026 (BRT), o [ensaio local do Jira](evidencias/JSM_LOCAL.md) confirmou abertura e conclusão automáticas de FIAP4-2 e notificações no Discord. A recuperação do serviço foi manual. Faltam aceite acadêmico do JSM, configuração no EKS, ensaio integrado com Self-Healing e capturas finais. A janela AWS de 72 horas ainda não iniciou.

Meta: Marcelo entregar o ambiente ensaiado e o pacote completo até **12/11/2026**, para Vinicius gravar o vídeo. Entrega acadêmica informada: **15/11/2026**. O vídeo deve ter **até 25 minutos**; o roteiro abaixo ocupa 23 minutos e reserva dois minutos de margem. O horário de fechamento do portal ainda deve ser confirmado.

## Responsabilidades

| Responsável | Entrega |
|---|---|
| Marcelo | Preparar EKS, IaC, GitOps, imagens e integrações; organizar acessos acadêmicos; executar o ensaio completo; corrigir falhas; entregar links, comandos, evidências e versões demonstradas. |
| Vinicius | Gravar a demonstração do ambiente já liberado, conferir áudio/legibilidade/tempo e revisar o vídeo completo. Não assumir implementação, provisionamento ou correções de última hora. |

Se um requisito não funcionar durante o ensaio, volta para Marcelo antes da gravação. Se falhar durante a gravação, registre o problema e interrompa essa prova; não substitua a automação por ação manual nem narre resultado que não apareceu.

## Estado confirmado e pendências

| Item | Situação em 10/11/2026 (BRT) | Limite da evidência |
|---|---|---|
| Cinco serviços em Docker | Smoke local aprovado; cinco health checks 200 e avaliação `true`. | Não comprova implantação no EKS. |
| Fluxo distribuído | NRQL confirmou na conta própria `8718919` 17 spans e 17 IDs únicos dos cinco serviços, raiz única e cadeia SQS send → process → acknowledge correlacionada. | Waterfall e Service Map dos cinco serviços conferidos; origem Docker/LocalStack. Capturas finais e repetição no EKS pendentes. |
| Evento de negócio | Evento correspondente localizado no DynamoDB do LocalStack. | Não comprova DynamoDB/SQS da AWS. |
| Três sinais | Métricas no Prometheus, logs OTLP correlacionados e nove linhas correspondentes no Loki para o trace do smoke. | Integração Docker local. |
| Testes e build | 36 testes Python dos serviços; testes Go com race detector, vet e lint; 15 testes do runbook; builds Docker aprovados. | Testes locais; Kubernetes e integrações externas não são simulados como prova final. |
| CI remoto | Base inicial aprovada; correção da raiz em `7c399ce` também aprovada no pipeline evaluation e na integração, com 17 spans dos cinco serviços e raiz real. [Execuções e commits](evidencias/CI_BOOTSTRAP.md). | ECR, promoção GitOps e plan/apply cloud ainda desabilitados. A integração do CI não envia dados ao New Relic nem comprova implantação. |
| Configurações da stack | Helm/Kustomize, configurações Collector/Loki, Promtool e provisionamento Grafana conferidos localmente. | Renderização/configuração válida não significa instalação no cluster. |
| Segurança local | SCA dos seis serviços e scan das seis imagens passaram no filtro CRITICAL com correção disponível, após corrigir quatro imagens Python. Smoke repetido com as novas imagens passou. | Gate local; não substitui os pipelines remotos ou scan das futuras imagens publicadas. |
| AWS acadêmica | Inventário não encontrou EKS, RDS ou ECR; bucket de backend existente. Prévia infra: 115 criações, zero alterações e zero exclusões. | Consulta/plan; nenhum apply. Plataforma ainda depende do cluster. |
| New Relic | Conta própria `8718919`, região US e ingestão confirmadas. Marcelo Full platform abre o APM sem upgrade. Plan Summary confirmou franquias gratuitas de um Full e 100 GB. | Service Map dos cinco serviços conferido: evaluation → analytics/targeting/flag e flag/targeting → auth. Waterfall conferido; capturas finais e benefício Students pendentes. |
| Incidentes via JSM | No [ensaio local do Jira](evidencias/JSM_LOCAL.md), o alerta abriu e fechou no Operations, e a Automation criou FIAP4-2 e o moveu para `Completed`. | Origem Docker, recuperação manual. O GitOps local já declara JSM na Application e no ExternalSecret. Publicação e ensaio EKS pendentes. |
| Substituição acadêmica | Marcelo escolheu JSM após o bloqueio de cadastro PagerDuty, sem conta PagerDuty ativa confirmada. | Enunciado, páginas 5–6, nomeia PagerDuty ou Opsgenie. Aceite do professor para JSM pendente; configurar a ferramenta não equivale a cumprir essa escolha literal. |
| ChatOps local | Alerta real `AuthHigh5xx` no Grafana 12.3.1 enviou Firing e Resolved ao Discord, com o mesmo fingerprint e início do episódio. | Origem Docker `fiap4`; recuperação manual de auth. Mensagens conferidas na interface, sem imagem salva. Repetição integrada no EKS pendente. |
| Self-Healing | Código e configuração preparados, sem prova integrada no cluster. | O restart manual do ensaio Discord não comprova mitigação automática. Não liberado para gravação. |

Evidência local: [relatório sanitizado do smoke](evidencias/LOCAL_SMOKE.json), execução de 09/11/2026 às 17:48 UTC, `passed=true`. Trace de referência: `0d935bf18337d21a6c85486083e49949`. Esse arquivo é evidência local e não deve ser apresentado como um trace já disponível no New Relic. A correção e os IDs das imagens estão na [evidência de segurança](evidencias/SECURITY_LOCAL.md).

A execução de 09/11 às 22:24 BRT confirmou localmente 17 spans e raiz real, também conferidos na conta anterior `8717927` por NRQL, incluindo o vínculo SQS: [evidência New Relic local](evidencias/NEW_RELIC_LOCAL.md) e [smoke correspondente](evidencias/NEW_RELIC_ROOT_SMOKE.json). Essas provas são históricas; não comprovam migração para a conta própria, ensaio no EKS ou conferência visual do APM.

A nova prova na conta própria, `20261110T020854-c83b67ed`, ocorreu em 09/11 às 23:08 BRT. O trace `9089a13d6ec55e445e59dc738b0d6a16` teve 17 spans e 17 IDs únicos dos cinco serviços, uma raiz e cadeia SQS send → process → acknowledge conferidos no SaaS por NRQL. [Evidência da conta própria](evidencias/NEW_RELIC_CONTA_PROPRIA.md). O Service Map dos cinco serviços e o waterfall desse trace também foram conferidos visualmente. A UI do trace exibiu 17 spans, zero erros e 86,09 ms, com send → process de analytics → DynamoDB/acknowledge visíveis. O alcance continua Docker/LocalStack; capturas finais e ensaio EKS ainda estão pendentes.

A [prova do Discord local](evidencias/DISCORD_LOCAL.md), em 10/11, confirmou Firing e Resolved para o episódio iniciado às 15:55:40 UTC e encerrado às 15:57:20 UTC (12:55:40–12:57:20 BRT), fingerprint `ce3ccb76701c998b`. Foram conferidas dez respostas `/validate` 200 antes, 503 durante e 200 após o restart **manual** de auth. Ao final, Grafana ficou `inactive`/`health ok`. Somente Discord estava habilitado; PagerDuty e responder não participaram. Essa evidência não comprova Self-Healing nem EKS; as imagens para o PDF ainda precisam ser salvas.

## Condições para Marcelo liberar a gravação

Todas as condições abaixo precisam de evidência recente do ambiente que será gravado:

- [ ] Aceite do professor para usar JSM no requisito que nomeia PagerDuty/Opsgenie registrado.
- [ ] [Gate JSM antes do EKS](RUNBOOK.md#gate-jsm-antes-do-eks) concluído: teste real local/SaaS, Secrets Manager/ExternalSecrets e overlay da Application coerentes, sem depender da chave PagerDuty da base anterior.
- [ ] Conta/profile/contexto acadêmico conferidos; EKS provisionado por Terraform após revisão do plano.
- [ ] Imagens da fase 4 publicadas e cinco serviços disponíveis; pipelines DevSecOps e GitOps preservados.
- [ ] ArgoCD mostra as aplicações esperadas sincronizadas e saudáveis, com a stack de observabilidade.
- [ ] Dashboard customizado mostra recursos do cluster, requisições dos serviços e logs atuais; Loki recebe logs dos contêineres do cluster.
- [ ] Collector roteia métricas, logs e traces; não há falha persistente de exportação.
- [ ] Requisição de demonstração encontrada no New Relic pelo `trace_id`, com percurso HTTP, SQS, analytics e DynamoDB.
- [ ] Service Map real mostra os cinco microsserviços e suas dependências.
- [ ] Falha controlada provoca alerta `AuthHigh5xx` em **Firing**, alerta no JSM Operations, incidente real no FIAP4 e notificação detalhada no canal acadêmico. Repetição do firing não cria outro incidente do mesmo episódio; resolved encerra o alerta e o incidente correspondente.
- [ ] O mesmo alerta aciona o runbook, que solicita e acompanha o rollout de `auth-service` automaticamente.
- [ ] Novas requisições válidas, queda da taxa de erros e normalização do alerta comprovam recuperação funcional.
- [ ] Quatro prints obrigatórios capturados e legíveis; links de código/vídeo e identificação dos participantes preparados.
- [ ] Ensaio completo cronometrado, sem credenciais visíveis; acessos conferidos na máquina de Vinicius.

Marcelo registra a liberação com data/hora, commit das aplicações, commit GitOps, imagens, cluster/contexto e resultado do ensaio. Enquanto houver item aberto, mantenha o aviso do topo.

## Pacote que Vinicius deve receber até 12/11

1. Links dos repositórios e commits exatos demonstrados, diagrama final e versão deste roteiro.
2. Links/telas de Grafana, ArgoCD, New Relic, JSM Operations/FIAP4 e canal acadêmico; acesso individual já testado, sem chaves ou webhooks dentro do documento.
3. [Comandos de demonstração](COMANDOS_DEMO.md) revisados e terminais preparados. O script lê somente as chaves necessárias em memória.
4. Identificadores do ensaio: trace, incidente, episódio do runbook e horários, vinculados à mesma falha.
5. Quatro prints obrigatórios e evidências complementares, com dados legíveis e sem credenciais.
6. Relatório PDF preparado para acrescentar o link do vídeo e a identificação final dos participantes.

Este arquivo não envia uma mensagem ao Vinicius nem concede acesso automaticamente.

## Contas acadêmicas a preparar

A conta própria New Relic `8718919`, região US, recebeu os traces dos cinco serviços, conferidos por NRQL. A gestão de usuários mostra um único usuário, Marcelo Garcia, com tipo Full platform, que abre o APM sem upgrade. O Plan Summary confirmou franquias gratuitas de um Full e 100 GB de ingestão. O Service Map foi conferido com cinco nós e relações evaluation → analytics/targeting/flag e flag/targeting → auth. O waterfall dos cinco serviços também foi conferido, incluindo o trecho SQS/analytics. As capturas finais ainda não foram salvas para o PDF. A evidência da conta anterior `8717927` permanece histórica. Para incidentes, a escolha atual é JSM, com a preparação e os limites descritos abaixo. Usar os dados de cadastro combinados fora do documento, sem publicar e-mails pessoais ou senhas.

1. **Conta New Relic própria:** selecionar explicitamente a conta `8718919`, cuja [região](https://docs.newrelic.com/docs/accounts/accounts-billing/account-setup/choose-your-data-center/) US está confirmada, e manter o endpoint do Collector alinhado a esse destino. A nova ingestão foi comprovada; preservar separadamente as evidências de cada conta e repetir o fluxo no ensaio EKS.
2. **Benefício Students:** a [documentação oficial](https://docs.newrelic.com/docs/accounts/accounts-billing/account-setup/student-program/), consultada em 09/11/2026, anuncia 500 GB/mês e três usuários completos por dois anos, mas informa que o **self-service está indisponível** e orienta solicitar provisionamento ao suporte. O fluxo OAuth GitHub ainda aparece na página, porém está condicionado à retomada do self-service; não presumir ativação automática. A [abertura de caso depende do plano de suporte](https://docs.newrelic.com/docs/new-relic-solutions/solve-common-issues/find-help-get-support/), portanto conferir a opção na conta. A solicitação só estará concluída quando o benefício estiver visivelmente aplicado.
3. **Comprovação estudantil:** para o caminho [GitHub Education](https://docs.github.com/en/education/about-github-education/github-education-for-students/apply-to-github-education-as-a-student), confirmar conta pessoal e matrícula atual, com documento aceito, como carteira estudantil com data, histórico ou declaração. O GitHub pode exigir e-mail acadêmico conforme a instituição; Gmail sozinho não garante elegibilidade.
4. **Acesso para gravar:** o [Free Tier comum](https://newrelic.com/pricing/free-tier) tem 100 GB/mês e somente um usuário completo, franquias confirmadas no Plan Summary da conta própria. A restrição prevista para [usuários Basic](https://docs.newrelic.com/docs/accounts/accounts-billing/new-relic-one-user-management/user-type/) foi observada na conta anterior. Marcelo Full platform já abre o APM e o Service Map; o mapa com todos os cinco serviços foi conferido. O waterfall também foi conferido; as capturas finais ainda precisam ser salvas. Definir com Vinicius os acessos e a forma de gravação, mantendo logins individuais: o Full de Marcelo não comprova Full de Vinicius. Nenhum upgrade foi ativado.
5. **JSM escolhido:** o projeto FIAP4 usa a [integração Grafana/Operations](https://support.atlassian.com/jira-service-management-cloud/docs/integrate-with-grafana/) para o alerta e uma regra separada de Jira Automation para o incidente. O [ensaio local do Jira](evidencias/JSM_LOCAL.md) confirmou o fluxo com a transição `Open → Completed`. A deduplicação de reenvios ainda não foi ensaiada. A publicação do GitOps, a sincronização no EKS e o aceite acadêmico continuam pendentes.
6. **Discord:** servidor separado **FIAP — ToggleMaster Fase 4**, canal **#alertas-fase4** e webhook Grafana FIAP criados. O alerta real do Grafana local entregou Firing e Resolved em 10/11, com recuperação manual entre os estados. Mensagens conferidas na interface; salvar as capturas finais e repetir o fluxo integrado no EKS, incluindo JSM e Self-Healing.
7. **Segredos e GitOps:** cumprir o [gate JSM antes do EKS](RUNBOOK.md#gate-jsm-antes-do-eks). Preparar os valores do Secrets Manager, publicar o GitOps e conferir as referências do Grafana e do Collector antes do ensaio. Nenhum valor pertence ao Git, às capturas ou ao roteiro.

Histórico PagerDuty: o SUBMIT retornou erro genérico, sem conta ativa confirmada; o suporte confirmou o caso `00867289`, ainda sem liberação observada. Restrição de domínio permaneceu hipótese, não diagnóstico fechado. A escolha por JSM substitui a tentativa de desbloqueio como caminho técnico atual; não reenviar a solicitação de suporte nem usar contas de outros projetos.

**Prazo:** não há prazo garantido identificado para a aprovação GitHub ou o provisionamento Students pelo suporte. Os [5–10 dias úteis publicados](https://newrelic.com/students-verification) referem-se aos outros parceiros, não ao caminho GitHub. A meta de 12/11 depende dessas validações e do ensaio; criar a conta Free não comprova o benefício educacional nem libera a gravação.

Para solicitar o benefício Students, o titular pode adaptar a mensagem abaixo ao suporte. É um rascunho; nenhuma mensagem foi enviada:

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

Esta preparação pressupõe que o gate JSM e os critérios de liberação acima tenham sido concluídos; a revisão JSM deve estar publicada e sincronizada. Não grave a preparação dos acessos ou telas de Secret. Abra antes as abas de ArgoCD, dashboard/Explore/alerta Grafana, APM, JSM Operations, incidente FIAP4 e ChatOps. Mantenha um terminal para carga, outro para os comandos e outro para logs/pods do runbook, conforme [RUNBOOK.md](RUNBOOK.md).

## Roteiro de 23 minutos

| Tempo | Ação e explicação | Prova que deve aparecer |
|---|---|---|
| 00:00–02:00 | Apresentar ToggleMaster, cinco serviços e a falha silenciosa que motivou a fase 4. Mostrar o diagrama HTTP → cache/serviços → SQS → analytics. | Arquitetura real e objetivo da observabilidade/resposta automática. |
| 02:00–05:00 | Mostrar IaC, pipelines DevSecOps e ArgoCD com a nova stack. Não executar um provisionamento inteiro no vídeo. | EKS existente, recursos declarados, aplicações sincronizadas/saudáveis e imagens/commits do ensaio. |
| 05:00–09:00 | Abrir dashboard customizado e Loki Explore. Explicar Collector central, agente de logs dos nós e destinos Prometheus/Loki/APM. | Recursos do cluster, taxas HTTP, logs recentes e dados dos serviços. Capturar print do dashboard. |
| 09:00–13:00 | Executar `prepare` e `trace`; localizar o ID no New Relic. Abrir spans detalhados e Service Map. | Cinco serviços, vínculos HTTP e salto assíncrono SQS/analytics; print do trace. |
| 13:00–20:00 | Iniciar carga, ativar falha em outro terminal e acompanhar os resultados do mesmo episódio. | Após a migração e o ensaio, Firing aciona JSM Operations, Jira Automation, ChatOps e runbook em paralelo, sem ordem garantida. Mostrar alerta, incidente FIAP4, mensagem, execução automática, pods novos e requisições recuperadas. Capturar prints de ChatOps e execução. |
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

No cenário JSM a liberar, Operations, Jira Automation, Discord e o runbook recebem o alerta em paralelo. A ordem de chegada e confirmação pode variar; conferir alerta, incidente FIAP4, ChatOps e mitigação do mesmo episódio, sem depender de uma sequência fixa. O fechamento do alerta Operations e a resolução do incidente FIAP4 precisam de provas separadas.

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
| Complementares | Service Map dos cinco serviços, Firing, alerta Operations e incidente FIAP4 criado/resolvido, ArgoCD, pods antes/depois e requisições recuperadas. |

Vinicius revisa o vídeo inteiro: até 25 minutos, áudio compreensível, textos legíveis e nenhuma credencial exibida. Marcelo confere no PDF os nomes, RMs, usernames, links de repositórios e vídeo, os quatro prints e a justificativa da arquitetura OTel e das escolhas New Relic/JSM, com o aceite do professor para a substituição. Confirmar acesso aos links pelo avaliador antes da submissão.

## Metas de preparação

| Data | Meta | Responsável |
|---|---|---|
| 10/11/2026 | Infraestrutura acadêmica e integrações; primeira prova no APM e nos canais de incidente. | Marcelo |
| 11/11/2026 | Ensaio ponta a ponta, correções e capturas; cronometrar o cenário automático. | Marcelo |
| 12/11/2026 | Pacote e ambiente liberados para Vinicius após os critérios de aceite. | Marcelo entrega; Vinicius confere acessos e gravação. |
| 15/11/2026 | Submissão acadêmica, dentro do horário do portal a confirmar. | Equipe |

São metas, não marcos concluídos. A fidelidade ao enunciado depende de mostrar os requisitos operando, não somente configurados.
