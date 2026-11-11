# Grafana, Jira Service Management e Discord — ensaio local

Em **10/11/2026**, a regra `AuthHigh5xx` do Grafana **12.3.1** disparou a partir de erros reais do `auth-service` na stack Docker acadêmica `fiap4`. A aplicação estava em `f6e7259`, com a base GitOps `0c760b4` e o candidato local `grafana-jsm.yaml`. O ensaio usou os receivers JSM Operations, Jira Automation e Discord. O responder ficou fora do ensaio.

Os cinco serviços responderam `200` em `/health`. Dez amostras de `/validate` retornaram `200` antes da falha, `503` durante a falha controlada e `200` após o restart manual de `auth-service`.

| Evidência de Firing | Resultado observado |
|---|---|
| Grafana | `AuthHigh5xx` em `firing`, saúde `ok`, uma entrada de alerta. |
| Jira Operations | [Alerta operacional](https://togglemaster-fiap-fase4.atlassian.net/jira/ops/alerts/c816275d-6dd4-4b91-b8e8-6579362911ea-1794334690482) em `Open`, atribuído à equipe FIAP - ToggleMaster. |
| Jira Automation | Execução `2a081844-9c4f-4fb3-a6cb-c0118b7ca34b` em `Success` às **15:18:10 BRT**. A auditoria registra a criação e a edição do item. |
| Incidente | [FIAP4-1](https://togglemaster-fiap-fase4.atlassian.net/browse/FIAP4-1) criado em `Open`, prioridade `High`, tipo de solicitação `Report a system problem`. |
| Discord | Mensagem `firing` recebida em `#alertas-fase4`, com início `2026-11-10T18:18:10Z` e fingerprint `ce3ccb76701c998b`. |

O incidente recebeu a label `grafana-ce3ccb76701c998b-20261110T181810Z`. O início diferencia este episódio do [ensaio anterior do Discord](DISCORD_LOCAL.md), que apresentou o mesmo fingerprint.

O episódio terminou às **15:22:00 BRT** (`18:22:00Z`). Operations fechou o alerta, e o Discord exibiu `resolved` com o mesmo início e fingerprint. A auditoria `9d11d673-e895-4342-8f44-78b27ac76b4e` localizou o FIAP4-1, mas registrou `Some errors`: o workflow recusou a transição de `Open` para `Resolved`. O incidente permaneceu `Open` apesar da nota automática que alegava atualização do status.

O workflow **FIAP4: Incident Management workflow for Jira Service Management** confirma que **Resolve** leva de `Open` a `Completed`. A regra foi ajustada para esse destino, e o comentário passou a registrar a chegada do `Resolved` sem afirmar mudança de status.

No segundo episódio, iniciado às **15:28:10 BRT** (`18:28:10Z`), o Grafana produziu um novo alerta no [Operations](https://togglemaster-fiap-fase4.atlassian.net/jira/ops/alerts/6180f76e-58e5-4d04-862e-6a933ea889b3-1794335290502), `Open`, e outra mensagem `firing` no Discord. A execução `1ab321e7-c4e9-456f-80ee-bfc3b59d1d5d` registrou `Success` e criou [FIAP4-2](https://togglemaster-fiap-fase4.atlassian.net/browse/FIAP4-2) em `Open`, prioridade `High`, com a label `grafana-ce3ccb76701c998b-20261110T182810Z`. O restart manual recuperou `/validate` para `200` nas dez amostras.

| Evidência de resolução após a correção | Resultado observado |
|---|---|
| Grafana | `AuthHigh5xx` voltou a `inactive`, saúde `ok`. |
| Discord | `resolved` no mesmo canal, mesmo fingerprint e início. Fim do episódio às **15:30:30 BRT** (`18:30:30Z`). |
| Jira Operations | O alerta do segundo episódio passou de `Open` a `Closed`. |
| Jira Automation | Execução `8d0378ed-7946-4403-a3e5-6720238fd1aa` em `Success` às **15:30:40 BRT**. |
| Incidente | FIAP4-2 passou de `Open` a `Completed`, com resolução `Done`. |

O FIAP4-1 permanece aberto como registro do primeiro ensaio. O segundo confirma a distinção entre episódios com o mesmo fingerprint. Reenvios do mesmo episódio e deduplicação sob concorrência continuam sem teste. A prova foi conferida nas interfaces e não inclui capturas de tela. Faltam aceite acadêmico do JSM, ativação do overlay e dos segredos no EKS, ensaio com Self-Healing e capturas finais.

A segunda carga produziu 1.800 requisições: 1.214 respostas `200`, 585 respostas `503` e uma falha de conexão durante o restart. Ao final, o Grafana foi pausado e removido, a stack local foi encerrada preservando os volumes e a consulta confirmou zero contêineres `fiap4`. Os arquivos temporários de transporte e acesso local estavam ausentes. A automação Jira ficou ativa.
