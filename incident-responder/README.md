# Runbook automático de incidente

Recebe o webhook do Grafana em `POST /webhook`, autenticado por Bearer token. Aceita somente alertas `firing` com `alertname=AuthHigh5xx`, `namespace=togglemaster` e `service=auth-service`, com início recente. O destino é fixo no código e limitado também pelo RBAC: somente `get` e `patch` no Deployment `togglemaster/auth-service`.

A ação altera a anotação `fiap.dev/incident-restart` do template do pod, solicita um rollout e acompanha sua conclusão. O AppProject/Application deve preservar especificamente essa anotação para o ArgoCD não desfazer o restart. A automação não executa comandos enviados pelo webhook.

O identificador de episódio combina fingerprint e início do alerta. SQLite em PVC registra a decisão antes de executar a ação. Uma repetição não causa novo restart, mesmo após reiniciar o runbook. Há cooldown de 10 minutos e no máximo uma tentativa por episódio. Falha de API ou rollout é registrada sem retry automático; a investigação humana continua necessária nesse caso. O serviço responde `202` antes de acompanhar o rollout, evitando timeout do webhook.

`rollout_completed` significa que as réplicas atualizadas ficaram disponíveis; **não afirma recuperação funcional**. A gravação deve mostrar também requisições voltando a funcionar e a taxa de erros caindo.

Testes locais:

```bash
python3 -m unittest discover -s incident-responder/tests -v
```

Os testes cobrem autenticação HTTP, concorrência, deduplicação persistente, cooldown, rejeição de alvos/timestamps inválidos, eventos resolvidos e falha sem vazamento de dados no log. O Kubernetes é substituído por um mock nesses testes. O teste final com alerta real, rollout no EKS, PagerDuty e ChatOps é uma etapa separada.

Configuração de produção acadêmica: `RESPONDER_TOKEN` vem de Secret via External Secrets; `STATE_DB=/data/actions.db`. A imagem usa Python sem dependências de terceiros. Não há endpoint público de entrada e não há leitura de secrets Kubernetes pelo runbook.

Referências: [webhook Grafana](https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/integrations/webhook-notifier/), [rollout de Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/).
