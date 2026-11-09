# Publicação e validação do CI — 09/11/2026

Os dois repositórios estão públicos: [aplicação/IaC](https://github.com/Marcelo6arcia/tech-challenge-fase-4) e [GitOps](https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4). A entrega anterior permaneceu intacta. Arquivos pessoais, configurações reais, planos brutos, state e chaves privadas não fazem parte dos commits.

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

As primeiras execuções da aplicação tiveram anotações `Internal server error` do GitHub antes de alguns jobs iniciarem. Foram feitas novas tentativas dos sete workflows, no commit `2a0424c`; elas também receberam erro interno. Os sete jobs efetivamente iniciados nessa segunda rodada passaram, mas **scans de imagem e integração não concluíram**. Exemplo: [integração, segunda tentativa](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42672215926). Não há aprovação integral do CI remoto.

No Terraform, foi corrigida a posição da trava de horário: análise estática não depende da janela cloud. As execuções seguintes falharam antes de criar jobs; [run 42672428590](https://github.com/Marcelo6arcia/tech-challenge-fase-4/actions/runs/42672428590) registrou erro interno com correlação `bd148d1f-5e7c-4a84-ae14-d7ca3948159f`. O teste remoto de criptografia sintética ainda precisa concluir.

No GitOps, [run 42672000778](https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4/actions/runs/42672000778) executou setup, Kustomize e cinco Helm templates, mas promtool não conseguiu ler o diretório temporário privado no Linux. A correção usa o UID/GID do proprietário do arquivo, preservando diretório privado e mount somente leitura. A causa foi reproduzida em Linux e os quatro cenários passaram localmente. Publicada em `f5171a6`; o [run seguinte](https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4/actions/runs/42672453170) falhou antes dos jobs com erro interno, correlação `2cbc9da0-622c-4aa9-96e1-c874d09e0f76`.

O status oficial consultado não indicava incidente geral; os erros acima são evidência destas execuções, não prova de indisponibilidade global. Repetir os workflows após a recuperação e registrar os resultados recentes antes de habilitar deploy. Nenhum gate foi removido para obter resultado verde.
