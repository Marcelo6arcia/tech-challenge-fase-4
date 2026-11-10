# ToggleMaster fase 4

Aplicação, infraestrutura e CI da fase 4 do Tech Challenge FIAP. O GitOps fica no repositório irmão `../togglemaster-gitops`. Esta cópia preserva a entrega anterior e adiciona observabilidade e resposta automática a incidente.

**Estado em 09/11/2026 (BRT): implementação, integração local, CI remoto e ingestão de traces no New Relic validados; NÃO LIBERADO PARA GRAVAÇÃO.** Faltam o ensaio no EKS, as capturas finais, PagerDuty, ChatOps e Self-Healing no cluster. A janela AWS de 72 horas ainda não iniciou. Pacote para Vinicius: 12/11. Entrega acadêmica: 15/11.

## Executar a prova local

Pré-requisitos: Docker com Compose e Python 3. A stack usa somente o projeto Compose `fiap4`, com endpoints publicados em loopback.

```bash
python3 scripts/local-env.py
docker compose -p fiap4 --env-file .env.local up -d --build
python3 scripts/local-smoke.py --report .runs/local-smoke.json
```

O primeiro comando gera valores aleatórios locais e preserva um arquivo existente. O teste cria dados sintéticos, valida avaliação/DynamoDB local e exige um trace conectado entre os cinco serviços, logs correlacionados e métricas nos backends reais. Não faz chamadas à AWS real.

Para encerrar os contêineres locais preservando os dados:

```bash
docker compose -p fiap4 --env-file .env.local down
```

Não compartilhar `.env.local`, states, planos binários ou configuração expandida do Compose. `.runs/` contém saídas de teste e planos locais ignorados pelo Git.

## Estrutura

| Diretório | Função |
|---|---|
| `auth-service`, `evaluation-service` | Serviços Go instrumentados |
| `flag-service`, `targeting-service`, `analytics-service` | Serviços Python instrumentados; analytics processa SQS |
| `incident-responder` | Runbook autenticado e limitado ao restart do auth |
| `terraform` | Infraestrutura AWS e bootstrap da plataforma |
| `.github/workflows` | CI DevSecOps, teste integrado e promoção ao GitOps |
| `local` e `localstack` | Dependências da integração local |
| `scripts` | Provas locais, comandos de demonstração e planos Terraform |
| `docs` | Evidências de validação, handoff e operação |

O responder é uma automação operacional; o ecossistema continua com cinco microsserviços de negócio.

## Validações executadas

- Go: testes com race detector, vet e linter nos dois serviços.
- Python: 36 testes dos três serviços, lint e gate Bandit.
- Runbook: 15 testes de autenticação, deduplicação persistente, concorrência, resolução atrasada e rollout correto; build Docker local.
- Stack Docker: health dos cinco serviços, avaliação `true`, evento DynamoDB, trace ligado dos cinco serviços com 17 spans e logs correlacionados no Loki. Prometheus recebeu métricas reais através do Collector.
- New Relic: a conta própria `8718919`, região US, recebeu 17 spans com 17 IDs únicos dos cinco serviços, raiz única e cadeia SQS send → process → acknowledge confirmados por NRQL, com origem Docker/LocalStack. Marcelo Full platform abre o APM sem upgrade; franquias gratuitas de um Full e 100 GB confirmadas. O Service Map foi conferido com cinco nós e relações evaluation → analytics/targeting/flag e flag/targeting → auth. O waterfall também foi conferido: 17 spans, zero erros exibidos, 86,09 ms no trace e trecho assíncrono até analytics/DynamoDB/acknowledge visível. Capturas finais ainda não foram salvas. [Nova evidência](docs/evidencias/NEW_RELIC_CONTA_PROPRIA.md); [histórico da conta `8717927`](docs/evidencias/NEW_RELIC_LOCAL.md) preservado.
- Falha local: `/validate` retornou 503 enquanto `/health` continuou 200; restart local de limpeza removeu a falha. **Esse teste não é a prova de Self-Healing no cluster.**
- Terraform: fmt/validate e prévia da infraestrutura com 115 criações, zero alterações e zero exclusões. Nenhum apply.
- Segurança: SCA dos seis serviços e seis imagens aprovadas no filtro CRITICAL com correção disponível do CI. Quatro imagens Python corrigidas e integração repetida após o rebuild. [Evidência do gate](docs/evidencias/SECURITY_LOCAL.md) e [smoke final](docs/evidencias/LOCAL_SMOKE.json).

As validações de Helm/Grafana/Collector estão no `README.md` do repositório GitOps da fase 4, disponível localmente em `../togglemaster-gitops`. Execuções GitHub Actions e aceitação em cloud são etapas diferentes; a implantação e a prova no ambiente final continuam pendentes.

O CI remoto da base anterior aprovou os seis pipelines de build/segurança, GitOps, integração completa e validação estática Terraform. A correção da raiz do trace em `7c399ce` também passou no pipeline evaluation e na integração remota, incluindo 17 spans dos cinco serviços com raiz real. Execuções e limites estão no [registro do CI](docs/evidencias/CI_BOOTSTRAP.md). Gravação e deploy não estão liberados.

## Preparar infraestrutura e CI

Repositórios públicos: [aplicação/IaC/CI](https://github.com/Marcelo6arcia/tech-challenge-fase-4) e [GitOps](https://github.com/Marcelo6arcia/togglemaster-gitops-fase-4). A entrega anterior foi preservada.

Antes de iniciar a janela AWS de 72 horas, concluir os acessos conforme [Contas acadêmicas a preparar](docs/HANDOFF_VINICIUS.md#contas-acadêmicas-a-preparar). A conta própria `8718919` já tem região US, acesso Full e ingestão comprovados; o Service Map dos cinco serviços já foi conferido. O waterfall também foi conferido; as capturas finais ainda precisam ser salvas. A tentativa de SUBMIT do PagerDuty retornou erro genérico, sem conta ativa confirmada. Restrição a e-mail gratuito é hipótese apoiada na documentação, não a causa comprovada desse erro. Benefício Students e acessos individuais continuam verificações separadas.

1. Configurar `GITOPS_REPO`, roles OIDC, bucket de state e CIDRs permitidos. A promoção usa `GITOPS_SSH_KEY`, exclusiva do GitOps. O ID do novo repositório está declarado no Terraform. `DEPLOY_ENABLED=false` mantém testes, segurança e build/scan ativos, sem publicação ou promoção; `INFRA_ENABLED=false` mantém somente a análise estática de IaC.
2. Preencher arquivos locais de backend/tfvars a partir dos exemplos. Estados da fase 4 usam `togglemaster/fase4/infra.tfstate` e `togglemaster/fase4/platform.tfstate`.
3. Gerar e revisar o plano da infraestrutura antes de aplicar:

```bash
export FIAP_ACCOUNT_ID='ID-DA-CONTA-ACADEMICA'
./scripts/bootstrap.sh plan infra
# Somente depois de revisar/aprovar o plano:
./scripts/bootstrap.sh apply infra
```

4. Depois do cluster, configurar o contexto explícito `togglemaster-fase4`, preparar a camada platform e repetir `plan platform`/`apply platform`. A camada platform depende dos outputs reais da infraestrutura.
5. Publicar imagens pelos gates do CI; o ArgoCD aplica o GitOps. Nunca promover `SET_BY_CI` como imagem válida.
6. Preencher os valores das integrações pelo Secrets Manager, fora do Git: New Relic, PagerDuty e Discord. Validar o fluxo real antes de liberar a gravação.
7. Ao iniciar a janela autorizada de até 72 horas, registrar início/fim UTC e definir `CLOUD_EXPIRES_AT` no CI. Habilitar publicação somente após recursos e secrets disponíveis. A trava impede novas operações após a expiração; **não desliga recursos**. Planejar o encerramento com antecedência, conforme o runbook.

O pipeline Terraform publica apenas resumo de tipos/ações. O plano completo passa entre jobs criptografado com `TF_PLAN_KEY`; apply exige dispatch explícito e revisão no environment `aws-dev`. O bootstrap inicial local é necessário para criar as roles OIDC.

`bootstrap.sh` aplica exatamente o plano salvo, confere sua conta/hash e pede confirmação explícita. `destroy.sh` apenas prepara um plano de encerramento; `bootstrap.sh apply-destroy <camada>` aplica o plano `-destroy` revisado mediante confirmação `DESTRUIR <conta>`. Volumes com policy Retain e o load balancer exigem revisão no encerramento. Não inicializar outro backend nem reutilizar os estados da fase 3 por conveniência.

## Gravação e operação

- [Handoff para Vinicius](docs/HANDOFF_VINICIUS.md)
- [Comandos de demonstração](docs/COMANDOS_DEMO.md)
- [Runbook operacional](docs/RUNBOOK.md)
- [Runbook automático](incident-responder/README.md)

O pacote só é liberado após mostrar no ambiente acadêmico: dashboard, logs de contêineres, trace e mapa com cinco serviços, alerta Firing, incidente, notificação, execução automática e verificação funcional posterior. Os quatro prints exigidos e o vídeo de até 25 minutos devem corresponder ao mesmo ambiente/versão.
