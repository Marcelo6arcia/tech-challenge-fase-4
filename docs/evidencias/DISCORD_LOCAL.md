# Grafana → Discord — prova local

Em **10/11/2026**, a regra real `AuthHigh5xx` entrou em **Firing** e depois normalizou. O canal acadêmico **#alertas-fase4**, no servidor **FIAP — ToggleMaster Fase 4**, recebeu as mensagens **firing** e **resolved** do webhook **Grafana FIAP**. As duas foram conferidas na interface do Discord.

**Alcance:** Docker/Collector/Prometheus → Grafana → Discord. A recuperação foi um restart **manual** do `auth-service`. PagerDuty e o responder automático não participaram deste ensaio. Esta prova não libera a gravação nem substitui o ensaio integrado no EKS.

## Configuração demonstrada

- Aplicação: `827b12ead9e423b4715fc0f9c807a40305cba70a`.
- GitOps: `0c760b452b6e9814bed42520b1e49354e3a1ae0d`.
- Grafana **12.3.1**, chart **10.5.14**; configuração renderizada pelo Helm.
- Projeto Compose `fiap4`; Grafana em loopback. Somente o receiver Discord foi habilitado.
- Regra versionada: mais de 5% de respostas 5xx em `/validate`, mínimo de 20 requisições em um minuto, condição sustentada por 30 segundos e avaliação a cada 10 segundos. A regra começou pausada e foi armada após mais de um minuto de tráfego saudável.
- Os labels `environment=dev` e `namespace=togglemaster` foram preservados do GitOps; não indicam que este ensaio ocorreu em Kubernetes.

## Resultado observado

| Etapa | Horário UTC em 10/11 | Evidência |
|---|---|---|
| Antes da falha | 15:54:50 | Cinco `/health` com 200 e dez amostras `/validate` com 200; regra inativa e saudável. |
| Falha ativada | 15:54:51 | Endpoint de demonstração confirmou `fault_active=true`. |
| Firing | Início do episódio: 15:55:40 | Estado `firing`/saúde `ok` no Grafana e mensagem real no Discord. |
| Durante a falha | 15:56:11 | Dez amostras `/validate` com 503; os cinco `/health` continuaram 200. |
| Recuperação manual | Após a amostra de 15:56:11 | `docker compose restart auth-service`, restrito à stack local `fiap4`. |
| Recuperação funcional | 15:56:39 | Dez amostras `/validate` com 200 e cinco `/health` com 200. |
| Resolved | Fim do episódio: 15:57:20 | Regra voltou a `inactive`/saúde `ok`; segunda mensagem real recebida no mesmo canal. |

O episódio corresponde a **12:55:40–12:57:20 BRT**. As mensagens compartilham o início `2026-11-10T15:55:40Z` e a correlação **`ce3ccb76701c998b`**. Ambas incluem serviço, namespace, ambiente, severidade, condição, contexto e link do runbook; a resolução inclui o horário final.

A descrição versionada menciona a automação prevista no projeto. Neste ensaio local o receiver do runbook estava ausente: a execução observada foi manual, conforme registrado acima.

A carga a 5 requisições/s realizou **1.954 requisições em 390,69 segundos**: 1.540 respostas 200, 412 respostas 503 e duas falhas de conexão no intervalo do restart. Foi interrompida pelo operador após a confirmação de Resolved. O [registro JSON sanitizado](DISCORD_LOCAL.json) preserva as amostras HTTP, os estados do Grafana e a correlação conferida no Discord. Os horários de registro das amostras não substituem os horários de transição informados nas mensagens.

## Encerramento e limites

Após Resolved, a regra foi pausada, o Grafana removido e a stack `fiap4` encerrada sem remover volumes. A consulta Docker confirmou zero contêineres do projeto, e os arquivos temporários de transporte e acesso local estavam ausentes. O webhook permanece configurado no Discord para a integração acadêmica; seu valor não faz parte desta evidência.

Nenhum arquivo de captura de tela foi salvo nesta etapa; as mensagens foram conferidas na interface. As capturas finais devem ser produzidas no ensaio do ambiente que será gravado. Continuam pendentes PagerDuty, implantação e ensaio no EKS, mitigação automática e pacote final PDF/vídeo. A janela AWS de 72 horas ainda não começou.
