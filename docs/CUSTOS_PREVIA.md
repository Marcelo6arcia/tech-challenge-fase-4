# Prévia de custos — fase 4

Consulta em **09/11/2026**, região **us-east-1 (N. Virginia)**, valores em **USD**, sem impostos, câmbio, créditos promocionais ou descontos de Free Tier. Estimativa para decidir sobre o provisionamento; **nenhum recurso foi criado nesta análise**.

**Base estimada: US$ 7,75/dia para a infraestrutura planejada; US$ 8,59/dia incluindo a plataforma prevista. Para 72 horas: US$ 23,26 e US$ 25,78, respectivamente.** Esses valores são subtotais de capacidade, não um teto de cobrança: consumo variável e serviços externos estão separados abaixo.

## Escopo verificado

O plano salvo em `.runs/infra.tfplan` contém **115 criações, nenhuma alteração e nenhuma destruição**, no novo estado da fase 4. Foram extraídos em memória somente tipos, quantidades e tamanhos necessários ao cálculo; o JSON completo do plano não foi salvo neste documento.

- Um cluster EKS; três nós Linux On-Demand `t3a.medium`, cada um com disco gp3 de 30 GiB. Capacidade desejada: 3; limites do grupo: 2–5.
- Três bancos PostgreSQL `db.t3.micro`, Single-AZ, cada um com 20 GiB gp3. Limite de expansão configurado: 50 GiB por banco; retenção de backup: um dia.
- Um nó Redis `cache.t3.micro`; nove segredos no Secrets Manager; seis repositórios ECR; duas filas SQS; DynamoDB sob demanda; três grupos de logs com retenção de sete dias e VPC Flow Logs.
- Rede em duas zonas. **Nenhum NAT Gateway no plano.** Os nós usam sub-redes públicas: foram considerados três IPv4 públicos.

## Cálculo de capacidade

Preços unitários consultados no catálogo oficial **AWS Price List Query API / GetProducts**, filtros para `us-east-1`, sistema Linux e modalidade On-Demand quando aplicável. EKS e IPv4 foram conferidos também nas páginas oficiais. Valores mensais normalizados para **730 horas**; um dia corresponde a 24 horas e três dias a 72 horas. Arredondamento aplicado apenas na apresentação.

| Recurso | Quantidade e preço unitário | USD/dia | USD/72h | Fonte oficial |
|---|---|---:|---:|---|
| EKS, suporte padrão | 1 × US$ 0,10/h | 2,40 | 7,20 | [EKS](https://aws.amazon.com/eks/pricing/) |
| EC2 `t3a.medium` Linux | 3 × US$ 0,0376/h | 2,71 | 8,12 | [EC2 On-Demand](https://aws.amazon.com/ec2/pricing/on-demand/) |
| RDS PostgreSQL `db.t3.micro`, Single-AZ | 3 × US$ 0,018/h | 1,30 | 3,89 | [RDS PostgreSQL](https://aws.amazon.com/rds/postgresql/pricing/) |
| ElastiCache Redis `cache.t3.micro` | 1 × US$ 0,017/h | 0,41 | 1,22 | [ElastiCache](https://aws.amazon.com/elasticache/pricing/) |
| EBS gp3 dos nós | 90 GB × US$ 0,08/GB-mês | 0,24 | 0,71 | [EBS](https://aws.amazon.com/ebs/pricing/) |
| Armazenamento RDS gp3 | 60 GB × US$ 0,115/GB-mês | 0,23 | 0,68 | [RDS PostgreSQL](https://aws.amazon.com/rds/postgresql/pricing/) |
| Secrets Manager | 9 × US$ 0,40/segredo-mês | 0,12 | 0,36 | [Secrets Manager](https://aws.amazon.com/secrets-manager/pricing/) |
| IPv4 públicos dos nós | 3 × US$ 0,005/h | 0,36 | 1,08 | [VPC / IPv4](https://aws.amazon.com/vpc/pricing/) |
| **Subtotal do plano de infraestrutura** | | **7,75** | **23,26** | |
| NLB da plataforma, componente fixo | 1 × US$ 0,0225/h | 0,54 | 1,62 | [Elastic Load Balancing](https://aws.amazon.com/elasticloadbalancing/pricing/) |
| IPv4 do NLB, premissa: duas zonas | 2 × US$ 0,005/h | 0,24 | 0,72 | [VPC / IPv4](https://aws.amazon.com/vpc/pricing/) |
| PVCs da observabilidade em gp3 | 23 GB × US$ 0,08/GB-mês | 0,06 | 0,18 | [EBS](https://aws.amazon.com/ebs/pricing/) |
| **Subtotal com plataforma prevista** | | **8,59** | **25,78** | |

Os três últimos itens são **projeção do código**, fora do plano de infraestrutura: NLB público do ingress e discos de Prometheus (10 GiB), Loki (10 GiB), Grafana (2 GiB) e incident-responder (1 GiB). O plano real da camada `platform` depende da existência do cluster; confirmar esses recursos nesse plano e depois da reconciliação GitOps. Os novos repositórios remotos públicos foram criados em 09/11.

Para reproduzir a consulta, usar a [AWS Price List Query API](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/using-price-list-query-api.html). Identificadores públicos consultados:

| Item | SKU | Vigência retornada pela API |
|---|---|---|
| EC2 `t3a.medium` | `CEC547W2ASCGJKER` | 01/11/2026 |
| RDS `db.t3.micro` em execução | `TGN7QDJF2AGFU9XA` | 01/10/2026 |
| Redis `cache.t3.micro`, tarifa normal | `YJHUKPU3DN6YKD58` | 01/10/2026 |
| EBS gp3 | `JG3KUJMBRGHV3N8G` | 01/11/2026 |
| RDS gp3, Single-AZ | `KYVYY29G957PKY3B` | 01/10/2026 |
| NLB, hora | `YKBGGP5EBGDU9T5W` | 01/11/2026 |
| Secrets Manager, segredo | `BJ3PQ9BYGU6P632F` | 01/07/2025 |

## Consumo variável e limites

- Não estimados por falta de volume de uso: ingestão/armazenamento/consulta de CloudWatch e Flow Logs; armazenamento e operações ECR/S3; requisições SQS/DynamoDB/Secrets Manager; tráfego de saída e entre zonas; backups/snapshots excedentes; possíveis créditos de CPU das famílias T3/T3a.
- O NLB cobra também capacidade utilizada: **US$ 0,006/NLCU-hora**, conforme catálogo oficial consultado (SKU `XZ2DR556MD28P9WJ`). A tabela inclui somente sua tarifa horária fixa.
- A expansão dos bancos além de 20 GiB, nós adicionais ou volumes criados depois do plano aumentam o custo. O cálculo pressupõe três nós durante toda a janela. A existência de limite máximo de cinco nós não significa que cinco serão cobrados desde o início.
- New Relic, PagerDuty, demais integrações SaaS e consumo de CI não estão incluídos. Contas, planos e franquias ainda precisam ser definidos; não foi presumida gratuidade.
- EKS cobra **US$ 0,10/h por cluster em suporte padrão**, independentemente do tráfego. Não considerar o ambiente gratuito pelo nome “Free Tier”; créditos e benefícios da conta não foram verificados nem abatidos.
- As 72 horas contam a partir da criação dos recursos cobrados. Se ficarem ligados por mais tempo, o subtotal continua crescendo. Apenas parar aplicações não elimina a cobrança do cluster, bancos, nós e discos. Volumes com política `Retain` e snapshots podem permanecer após a remoção de aplicações; o encerramento deve conferir os recursos remanescentes.

Marcelo autorizou em 09/11 **somente 72 horas de ambiente**, ciente da estimativa de US$ 25,78 de capacidade mais consumo variável e impostos. O início será registrado quando o provisionamento começar, após os pré-requisitos das contas; nenhuma janela foi iniciada. Uma margem financeira não é um bloqueio automático de gastos; este documento não implementa desligamento nem limite de cobrança.
