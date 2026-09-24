# ScoutV2 — Índice de briefs

Decomposição de `docs/kanban/scoutv2/design.md` §6 em unidades de trabalho para o speckit
(`/speckit-specify` → `/speckit-plan`). Cada brief segue `docs/kanban/_brief-template.md`, com uma
adaptação: a seção 7 (Critérios de aceite) é subdividida por user story (`US1`…`USn`), para que o
corte das stories seja decidido aqui e não dentro do `/specify`.

Regra de corte usada: 3 user stories por brief; a quarta só existe quando mover a story para outro
documento separaria a remoção de um mecanismo da sua substituição (briefs 05 e 10).

| # | Brief | Fase no design | US | Depende de |
|---|---|---|---|---|
| 01 | [Loader e validação de playbooks](01-playbook-loader-e-validacao.md) | Fase 0 | 3 | — |
| 02 | [Roteador determinístico e estado por conversa](02-roteador-e-estado-de-conversa.md) | Fase 0 | 3 | 01 |
| 03 | [TurnRunner de playground e primeira playbook](03-turn-runner-playground.md) | Fase 0 | 3 | 02 |
| 04 | [Instructions tipadas, índice e `open_playbook`](04-instructions-indice-open-playbook.md) | Fase 1 | 3 | 03 |
| 05 | [Escalation, exits e desmonte do auditor](05-escalation-exits-desmonte-auditor.md) | Fase 1 | 4 | 04 |
| 06 | [Playbooks do primeiro corte](06-playbooks-primeiro-corte.md) | Fase 1 | 3 | 05 |
| 07 | [Capabilities e agendamento ponta a ponta](07-capabilities-e-agendamento.md) | Fase 2 | 3 | 06 |
| 08 | [Memória tipada de contato](08-memoria-tipada.md) | Fase 3 | 3 | 04 (só a linha de política em `Memory`) |
| 09 | [Conhecimento determinístico](09-conhecimento-deterministico.md) | Fase 4 | 3 | — |
| 10 | [Produção: `engine: v2`, promoção e depreciação](10-producao-engine-v2.md) | Fase 5 | 4 | 06, 07 |

**Caminho crítico:** 01 → 02 → 03 → 04 → 05 → 06 → 07 → 10.
**Paralelizáveis:** 08 e 09 são independentes entre si e do caminho crítico (design §6, "Fases 3 e 4
são independentes entre si e das anteriores"); 08 US1 (parar de injetar `to_llm_text`) pode ser
entregue a qualquer momento, inclusive antes do 04.

**Critério de corte do épico** (design §6, Fase 0): se o roteador do brief 02 não passar nas specs
sem LLM, o restante não vale a pena — não avançar para o 03.

Fora desta decomposição, por decisão explícita do design §6 (Fase 6, investigação futura): `ScoutTool`
como provider de capability (6.1), packs por vertical (6.2), materialização em banco (6.3), re-sync
de fonte (6.4), priorização de par autoral (6.5), reintrodução de auditoria (6.7).
