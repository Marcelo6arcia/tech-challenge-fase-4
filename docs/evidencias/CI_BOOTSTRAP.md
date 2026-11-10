# Publicação e validação do CI — 09/11/2026

Os dois repositórios estão públicos: [aplicação/IaC](https://github.com/Marcelo6arcia/tech-challenge-fase-4) e [GitOps](https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4). A entrega anterior permaneceu intacta. Arquivos pessoais, configurações reais, planos brutos, state e chaves privadas não fazem parte dos commits.

## Correção da raiz do trace — resultado mais recente

Commit `7c399ced7032dc7adfa62a78c28024a7db1e20f4`, publicado em 09/11/2026 (BRT):

- **Evaluation aprovado:** [42736310727](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42736310727). Cinco jobs de qualidade passaram: build/testes, lint, SAST, SCA e build/scan da imagem com SBOM. OIDC, ECR, push e promoção GitOps ficaram desabilitados/ignorados.
- **Integração aprovada:** [42736311082](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42736311082). Seis testes de descoberta/integridade do trace, smoke dos cinco serviços, 15 testes do runbook e encerramento da stack passaram.
- Artefato `validacao-local-fase4` (ID `13727740829`) conferido: `passed=true`, trace `af46f010cae33e24349703b62bd2af6f`, 17 spans, cinco serviços, `evaluation_server_is_root=true` e `analytics_consumer_parent_is_producer=true`. Execução 10/11/2026, 01:33:00–01:33:09 UTC (09/11, 22:33 BRT).

Este CI valida Docker no runner e não envia ao New Relic. A [prova de ingestão no SaaS](NEW_RELIC_LOCAL.md) usa outro trace, gerado no ambiente local. Nenhum gate foi removido; nenhuma nova tentativa foi necessária nestas duas execuções. A implantação AWS permanece pendente e a janela de 72 horas não iniciou.

## Validação da base inicial

- **GitOps aprovado:** [42674394167](https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4/actions/runs/42674394167), commit `f5171a6`.
- **Integração aprovada:** [42674019431](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42674019431), commit `574b58f`. Health, avaliação, DynamoDB local, trace ligado nos cinco serviços, logs OTLP/Loki e métricas Prometheus passaram; 15 testes do runbook passaram. Trace de referência `188fffc540ddb681c5b0d3fe239b14a2`. É prova Docker no runner, não APM/EKS.
- **Terraform estático aprovado:** [42674558325](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42674558325), commit `cf8071c`. Formatação, três testes das proteções, criptografia sintética, dez módulos, TFLint, Checkov e gate Trivy executaram com sucesso. Checkov permanece informativo conforme a política existente; sucesso do job não significa ausência de todos os achados. Plan/apply cloud foram ignorados por estarem desabilitados.
- **Seis pipelines individuais aprovados:** testes/build, lint, SAST, SCA, gate CRITICAL da imagem e SBOM concluídos. Publicação ECR e promoção GitOps ficaram desabilitadas, assim como OIDC/login AWS.

| Componente | Execução aprovada | Commit |
|---|---|---|
| auth-service | [42675235854](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42675235854) | `cf8071c` |
| evaluation-service | [42674536545](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42674536545) | `574b58f` |
| flag-service | [42675235593](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42675235593) | `cf8071c` |
| targeting-service | [42675235625](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42675235625) | `cf8071c` |
| analytics-service | [42675236134](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42675236134) | `cf8071c` |
| incident-responder | [42675236085](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42675236085) | `cf8071c` |

Os arquivos do evaluation, seu caller, workflow reutilizável e scripts do CI não mudaram entre `574b58f` e `cf8071c`. Foram confirmados 30 jobs de qualidade com sucesso nos seis pipelines. O responder é automação operacional; os microsserviços de negócio continuam sendo cinco.

## Configuração verificada

- `DEPLOY_ENABLED=false` e `INFRA_ENABLED=false`: CI executa validações locais; publicação ECR, promoção GitOps e operações Terraform cloud ficam desabilitadas.
- `GITOPS_REPO` aponta somente ao novo GitOps. Uma deploy key exclusiva tem escrita nesse repositório; a chave privada fica no secret `GITOPS_SSH_KEY` da aplicação. Configuração explicitamente autorizada por Marcelo.
- `TF_PLAN_KEY` foi cadastrado com autorização para criptografar planos antes de passá-los entre jobs. O resumo público não inclui valores nem outputs.
- Environment `aws-dev` permite somente `main` e tem Marcelo como revisor. Apply requer dispatch explícito, plano da mesma execução e janela `CLOUD_EXPIRES_AT` válida.
- As travas de janela impedem novas operações fora do período; não fazem desligamento. O encerramento está descrito na seção 12 do runbook. Nenhuma janela AWS foi iniciada.

## Verificações locais adicionais

- Actionlint 1.7.12 aprovou workflows de aplicação/Terraform/GitOps.
- Três testes das proteções do CI passaram: janela/fuso, rejeição de entradas inválidas ou fora de 72 horas e ausência de valores privados no resumo do plano.
- Quatro cenários isolados do bootstrap passaram com AWS/Terraform simulados: confirmação de destruição, conta divergente, seleção do plano `-destroy` e rejeição de hash alterado. Nenhum recurso foi excluído.
- Terraform fmt/validate passaram após restringir S3 às chaves da fase 4 e trocar token Kubernetes estático por autenticação renovável. A prévia atualizada continua em 115 criações, zero alterações e zero exclusões.
- TFLint local 0.62.1 passou no limiar de erros. O workflow ainda fixa 0.53.0; esse resultado local não substitui o resultado remoto dessa versão.
- Trivy 0.76.2 passou no filtro CRITICAL de IaC, com 13 arquivos de configuração detectados. Valores locais de backend/tfvars foram excluídos; variáveis sem valor limitam a análise estática. O scanner registrou as exceções de endpoint público EKS já existentes no código; o CIDR efetivo deve permanecer restrito a `/32`.

## Execuções remotas e limites

As primeiras execuções da aplicação tiveram anotações `Internal server error` do GitHub antes de alguns jobs iniciarem. Foram feitas novas tentativas dos sete workflows, no commit `2a0424c`; elas também receberam erro interno. Os sete jobs efetivamente iniciados nessa segunda rodada passaram, mas **scans de imagem e integração não concluíram**. Exemplo: [integração, segunda tentativa](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42672215926). Essas duas rodadas iniciais não comprovaram aprovação integral; as execuções aprovadas posteriores estão na tabela de resultados atuais acima.

No Terraform, foi corrigida a posição da trava de horário: análise estática não depende da janela cloud. As execuções seguintes falharam antes de criar jobs; [run 42672428590](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42672428590) registrou erro interno com correlação `bd148d1f-5e7c-4a84-ae14-d7ca3948159f`. A execução posterior [42673682282](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42673682282) completou formatação, três testes das proteções e a criptografia sintética. Ela encontrou uma variável de CIDR vazia no ambiente global durante o init isolado do módulo EKS; as variáveis cloud foram movidas para os jobs plan/apply, preservando a validação estática independente dos secrets. A rodada completa depois dessa correção passou no run `42674558325`, conforme o resultado atual acima.

No GitOps, [run 42672000778](https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4/actions/runs/42672000778) executou setup, Kustomize e cinco Helm templates, mas promtool não conseguiu ler o diretório temporário privado no Linux. A correção usa o UID/GID do proprietário do arquivo, preservando diretório privado e mount somente leitura. A causa foi reproduzida em Linux e os quatro cenários passaram localmente. Publicada em `f5171a6`; o [run seguinte](https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4/actions/runs/42672453170) falhou antes dos jobs com erro interno, correlação `2cbc9da0-622c-4aa9-96e1-c874d09e0f76`.

Depois dessa falha interna, o [run 42674394167](https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4/actions/runs/42674394167), no mesmo commit `f5171a6`, **passou integralmente**: Kustomize, cinco charts Helm, dashboard e quatro cenários do alerta. A correção de UID/GID está comprovada no runner Linux.

O status oficial consultado não indicava incidente geral; os erros acima são evidência destas execuções, não prova de indisponibilidade global. Os workflows foram repetidos e concluídos, conforme os resultados atuais acima. Nenhum gate foi removido para obter resultado verde. A prova de implantação em AWS/APM/incidente continua sendo uma etapa diferente, ainda pendente.


## Notificações de incidente — 09/11/2026, 23:38 BRT

A execução [42744168884](https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4/actions/runs/42744168884), no commit GitOps `0c760b452b6e9814bed42520b1e49354e3a1ae0d`, passou com o job `validate` e todas as etapas concluídas. O log confirmou Kustomize, os cinco charts, quatro cenários do alerta, igualdade do dashboard e o novo contrato de notificações: contatos, mensagens de resolução, agrupamento, templates após Helm e referências de Secrets.

O ajuste acrescenta horários UTC, condição/contexto e correlação ao Discord e aos detalhes do PagerDuty. Os templates firing/resolved também foram exercitados localmente com dados sintéticos. Nenhuma credencial real é necessária nesses validadores. Sucesso do CI não comprova cadastro PagerDuty, entrega Discord ou mitigação no EKS; essas provas permanecem separadas.
