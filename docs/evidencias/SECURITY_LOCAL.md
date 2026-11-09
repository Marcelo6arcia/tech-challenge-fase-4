# Segurança local — gate de vulnerabilidades

> **GATE LOCAL APROVADO em 09/11/2026 às 17:46 UTC:** seis imagens aprovadas no filtro CRITICAL com correção disponível. As quatro imagens Python inicialmente bloqueadas foram corrigidas, reconstruídas e aprovadas por novo scan. Nenhum gate foi enfraquecido. Isto não libera a gravação: o smoke com as novas imagens e as provas EKS/APM/PagerDuty/ChatOps/self-healing continuam separados desta evidência.

## Método e escopo

- Ferramenta: Trivy **0.76.2**, release oficial publicada em 05/11/2026, consultada em 09/11. [Release oficial](https://github.com/aquasecurity/trivy/releases/tag/v0.76.2).
- Binário macOS ARM64 obtido da release oficial; SHA-256 conferido contra o arquivo de checksums da mesma release: `ae7ea358326960406b703c77b2ac490190797d80b306b5b50c2a27221da0a5b8`.
- Base oficial `ghcr.io/aquasecurity/trivy-db:2`, atualizada em **09/11/2026 às 13:58:27 UTC**, baixada às 17:40:44 UTC.
- Rodada inicial: seis imagens locais por ID imutável e SCA dos seis diretórios de serviço. Após a correção: novo scan das quatro imagens alteradas; IDs de auth/evaluation permaneceram iguais. Scanner `vuln`, severidade `CRITICAL`, `--ignore-unfixed` e saída bloqueante `--exit-code 1`, conforme o filtro do pipeline existente. A [referência oficial do comando](https://trivy.dev/docs/latest/references/configuration/cli/trivy_image/) documenta essas opções.
- Após baixar a base, os scans usaram `--offline-scan`, sem atualização da base durante a rodada. Imagens obtidas somente pelo Docker Desktop local (`--image-src docker`), sem fallback para registry.
- Não houve scan de `.env`, workspace geral, credenciais ou outros projetos. Detector de secrets não foi executado. A correção alterou somente os quatro Dockerfiles Python permitidos e reconstruiu suas imagens locais. Containers temporários, sem rede e com entrada `dpkg-query`, confirmaram a versão instalada. Nenhum recurso cloud ou container da aplicação em execução foi alterado por esta etapa.

Os resultados brutos iniciais ficam em `.runs/security/`, ignorado pelo Git; o resumo estruturado está em `.runs/security/summary.json`. O rescan e a versão instalada estão em `.runs/security/after-remediation/summary.json`. A rodada inicial foi preservada. Este documento conserva os resultados necessários para revisão sem incluir segredos.

## Resultado por serviço

| Serviço | SCA do diretório | Scan inicial da imagem | Resultado final da imagem |
|---|---|---|---|
| auth-service | Passou, exit 0 | Passou, zero achados | Passou, mesmo ID |
| evaluation-service | Passou, exit 0 | Passou, zero achados | Passou, mesmo ID |
| flag-service | Passou, exit 0 | Bloqueou, 3 CRITICAL | Passou, exit 0, zero achados |
| targeting-service | Passou, exit 0 | Bloqueou, 3 CRITICAL | Passou, exit 0, zero achados |
| analytics-service | Passou, exit 0 | Bloqueou, 3 CRITICAL | Passou, exit 0, zero achados |
| incident-responder | Passou, exit 0 | Bloqueou, 3 CRITICAL | Passou, exit 0, zero achados |

Na rodada inicial foram **três CVEs distintos**, repetidos nas quatro imagens, totalizando doze ocorrências. O rescan não encontrou outro CRITICAL com correção disponível. A aprovação do SCA dos manifestos de dependências não cobre os pacotes de sistema da imagem; por isso o scan do container é um gate separado.

## Bloqueio encontrado e correção verificada

As quatro imagens afetadas usam Debian 13/Trixie e continham `perl-base` **5.40.1-6**. O Trivy indica **5.40.1-6+deb13u1** como versão corrigida. O Debian Security Tracker confirma essa correção para Trixie nas três entradas:

| CVE | Classificação observada | Referência primária |
|---|---|---|
| CVE-2026-13221 | CRITICAL no Trivy, severidade originada do NVD | [Debian Security Tracker](https://security-tracker.debian.org/tracker/CVE-2026-13221) |
| CVE-2026-42496 | CRITICAL no Trivy, severidade originada do NVD | [Debian Security Tracker](https://security-tracker.debian.org/tracker/CVE-2026-42496) |
| CVE-2026-8376 | CRITICAL no Trivy, severidade originada do NVD | [Debian Security Tracker](https://security-tracker.debian.org/tracker/CVE-2026-8376) |

O candidato **5.40.1-6+deb13u1** foi confirmado por `apt-cache policy perl-base` no repositório oficial `deb.debian.org/debian`, suíte Trixie. Os Dockerfiles agora instalam a atualização de `perl-base` no runtime e em cada builder Python utilizado, com `dpkg --compare-versions` exigindo pelo menos essa versão. Não foi executado `full-upgrade` nem adicionada exceção ao Trivy. As dependências de build e `libpq5` já existentes foram preservadas.

Os quatro builds terminaram com exit 0. `dpkg-query` executado em cada imagem final confirmou exatamente **5.40.1-6+deb13u1**. O rescan por seus novos IDs terminou com exit 0 entre **17:46:00 e 17:46:04 UTC de 09/11/2026**, usando a mesma base da rodada inicial. Código Python/Go e manifestos de dependências não mudaram nesta correção.

A recriação dos três serviços Python locais e o smoke integrado após estes builds ficam sob coordenação da etapa de validação funcional; sua execução não é atestada por este relatório. Não foi avaliada a explorabilidade dessas CVEs no fluxo da aplicação; o bloqueio corrigido foi o da política do pipeline.

## Identidade exata das imagens aprovadas

| Tag local na execução | ID Docker examinado |
|---|---|
| `fiap4-auth-service:latest` | `sha256:08be3a8bbe5858c248484848bbc27986e2a449969da14a1969cac56b7d0a4472` |
| `fiap4-evaluation-service:latest` | `sha256:97dfd87d9da9191e5e3aeeadcf02ca94a396b89dcf5d910281026feb5d3bba7d` |
| `fiap4-flag-service:latest` | `sha256:8e54f207f585ba8f7544556cf4bfc90d4d27afb491aea7e103d511559100e5b4` |
| `fiap4-targeting-service:latest` | `sha256:224dc5c0feba60190527ce8fb2ac05c1a12d0dc1bf20e560e0f7544c5f341b78` |
| `fiap4-analytics-service:latest` | `sha256:8371c148d573cef560120529df6058e102d5743332d32f4942f018e75b0360f7` |
| `fiap-phase4-incident-responder:review` | `sha256:17e0052c9c985b433e61c922a415002a8e53e33e40a262a784e2718c8fad8eb4` |

Tags locais podem mudar após um novo build. Estes resultados se aplicam aos IDs acima; não comprovam o estado de uma futura imagem no ECR ou no EKS.

Os IDs Python anteriores, bloqueados e preservados no resumo inicial, foram:

| Serviço | ID bloqueado antes da correção |
|---|---|
| flag-service | `sha256:8c62d65291afde98f05b64fba3bd353c972404bda1ed8f851759cdac8f726b23` |
| targeting-service | `sha256:20e51de79732134118c8bdcfdc5b4647a7f3df4fb0ac2847348ca2ccbf0caa82` |
| analytics-service | `sha256:f6189ae071be1a779791b59e6d3ce8dbea9e20d5799be5c86cfb7f86d2d09f19` |
| incident-responder | `sha256:5b9d7cec243604abeccbd0330aedf772361bb89a1d81ef0a243d37e690381e08` |

## Limites desta evidência

O filtro reproduz CRITICAL **com correção disponível**, como configurado no pipeline. Passar nesse filtro não significa ausência de HIGH, MEDIUM, CRITICAL sem correção ou riscos de configuração. Não é um scan completo de secrets, IaC ou acessibilidade da aplicação. Também não substitui a execução dos pipelines remotos ou a prova funcional no cluster.

## Revisão separada de arquivos publicáveis

Depois do gate de imagem, foram examinados os 242 arquivos candidatos à publicação dos dois repositórios, obtidos por `git ls-files --cached --others --exclude-standard`. Trivy secrets retornou zero achados; revisão complementar não encontrou segredo real ou referências indevidas a outros projetos. Configurações ignoradas e histórico Git ficaram fora desse escopo. Valores de testes e identificadores técnicos da conta FIAP foram diferenciados de credenciais. O staging estava vazio nos dois repositórios. Esse resultado é uma revisão do conjunto atual, não uma garantia sobre alterações futuras.
