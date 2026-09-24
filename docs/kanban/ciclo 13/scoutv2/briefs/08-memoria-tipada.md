# Fase 08 — Memória Tipada de Contato (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/scoutv2/design.md` §4.8 (memória), §6 (Fase 3 + item 6.6)
**Depends on**: Brief 04 apenas para a linha de política em `Instructions > Memory`. Fora isso é
**independente do caminho crítico** (design §6: "Fases 3 e 4 são independentes entre si e das
anteriores"), e a US1 pode ser entregue isolada, a qualquer momento.

---

## 1. Problema

Caso real já documentado no fork — Fase 32 do ciclo 10
(`docs/kanban/ciclo 10/scout/32-contact-memory-handoff-pretext-guardrail/spec-preview.md`, conta 2
"Dens Odontologia", conversas 44877 e 45006): uma nota gerada em 19/09 ("Solicitou explicitamente
falar com um atendente humano") foi lida três dias depois, numa conversa nova, como preferência
atual — o Scout transferiu um lead engajado citando, na mensagem pública, *"já tinha pedido para
falar direto com alguém da equipe"*. E o próprio handoff indevido gerou nova nota reforçando o
mesmo sinal: sem correção, a tendência piora a cada conversa.

O remédio aplicado no v1 foi um parágrafo sempre-on
(`custom/app/services/custom/scout/system_prompts_service.rb:134-141`) — mais uma regra global para
compensar um problema de dados.

Segundo caso, da mesma raiz: nota escrita por atendente ("cliente chato, manda pro humano") entra no
prompt como instrução acidental ao modelo.

## 2. Diagnóstico / Causa raiz

- `system_prompts_service.rb:96-102` (`contact_context_section`) injeta `@contact.to_llm_text` em
  toda conversa do contato.
- `app/services/llm_formatter/contact_llm_formatter.rb:19-20` (`build_notes`) faz
  `@record.notes.all.map { |note| " - #{note.content}" }` — **todas as notas, sem limite, sem filtro
  de origem, sem tipo**.
- `custom/app/services/custom/scout/contact_notes_service.rb:44-51` gera as notas por LLM ao fim da
  conversa **sem esquema** (lista de strings), e `:20,65-70` grava com prefixo de data — paliativo
  da Fase 32, que não separa fato de episódio.
- **Isso é regressão do fork, não herança**: o Captain monta contato por whitelist de campos
  (`enterprise/.../system_prompts_service.rb:428-435`; em V2, `snippets/contact.liquid`) e **nunca**
  injeta notas (design §1.3). O conserto mínimo é parar de usar `to_llm_text` no prompt.
- `app/models/note.rb:27` — `user_id` é opcional, e o Scout cria nota sem usuário: `notes.user_id IS
  NULL` **já identifica autoria do Scout**, sem coluna nova e sem parsing de prefixo.

## 3. Precedente

- **Botpress** não oferece mais que política em prosa: `Memory` é uma aba de `Instructions` —
  *"What the agent can retain about a user across conversations"*. As estruturas persistentes
  (Tables, `user.*`) pertencem ao Studio legado, não ao agente de Playbooks. Aplica-se a política;
  não há estrutura a copiar.
- **Letta/MemGPT** (core vs recall) e **Zep** (subgrafo semântico vs episódico) são a origem da
  tipagem `fato`/`episodio` — vai além do Botpress deliberadamente, porque resolve um caso medido
  aqui.
- **Captain V2**: o precedente negativo útil — não lê nota nenhuma e não tem o problema.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | Memória tipada em **dois tipos** (`fato` / `episodio`); só `fato` entra no prompt | Elimina estruturalmente o caso "transferido em 12/08 lido como preferência atual", hoje combatido com parágrafo sempre-on (design decisão 10) |
| 2 | **Gate por origem**: entra no prompt só nota escrita pelo Scout **e** classificada `fato` | Nota humana é sinal misto por natureza ("cliente chato, manda pro humano" é instrução acidental) e fica fora por padrão; o gate por origem dispensa classificar nota que ninguém vai ler |
| 3 | Origem detectada por `notes.user_id IS NULL`, **sem coluna nova e sem parsing de prefixo** | `user_id` já é opcional em `Note` (`note.rb:27`) e o Scout cria sem usuário |
| 4 | `kind` é classificado **no ato da escrita**, no mesmo schema da chamada que já existe | `ContactNotesService` pede hoje `{ notes: ['…'] }`; passa a pedir `{ notes: [{ kind, content }] }` — **zero LLM adicional, zero job de classificação** |
| 5 | Conteúdo mora **uma vez só**, em `notes` (tabela upstream); a tabela do fork guarda só `note_id` + `kind`, com `ON DELETE CASCADE` | Editar no Chatwoot altera o que o Scout lê porque é o mesmo registro — sem código de sincronização. Excluir remove o atributo por cascade |
| 6 | **Sem gancho no ciclo de vida de `Note`** e sem entrada de MANIFEST | Só o Scout escreve nota classificável, então `app/models/note.rb` continua intocado (design §4.8) |
| 7 | **Sem migração, sem backfill** | Nota antiga não tem linha de atributo, logo não entra no prompt; o histórico volta a alimentar o modelo à medida que o Scout escreve notas novas — e nesse meio-tempo o comportamento é o do Captain, que nunca leu nota nenhuma |
| 8 | Promoção manual de nota humana é **parte deste corte**, não investigação futura | É a única porta de entrada de nota humana no prompt; sem ela, o gate da decisão 2 não tem escape legítimo (design §6.6) |
| 9 | Conflito entre notas resolve-se por **recência**, com uma linha em `Instructions > Memory` | Regra durável, na camada certa — e não mais um parágrafo situacional no balde global |

## 5. Escopo preliminar

- `custom/app/services/custom/scout_v2/` (montagem do contexto de contato): whitelist de campos, sem
  `to_llm_text`.
- `custom/app/services/custom/scout/contact_notes_service.rb`: schema `{ kind, content }` na mesma
  chamada; gravação do atributo junto com a nota.
- Migração + modelo `ichatr_scout_note_attributes`: `note_id` (FK → `notes`, `ON DELETE CASCADE`),
  `kind` (`fato` | `episodio`).
- Consulta de contexto: notas do contato com `user_id IS NULL` e `kind: fato`, top N por recência.
- Ação de promoção de nota humana (marcar "usar como fato"), gravando a linha de atributo para uma
  nota com `user_id` — auditável e opt-in.
- `Instructions > Memory`: política de retenção + regra de recência.

## 6. Fora de escopo

- Qualquer alteração em `app/services/llm_formatter/contact_llm_formatter.rb` ou em `app/models/
  note.rb` (upstream, compartilhados com o Captain) — o v2 simplesmente deixa de chamar o formatter.
- O prompt do v1: `contact_context_section` e `memory_notes_warning` continuam como estão para
  scouts em `engine: v1`; a remoção é da depreciação (brief 10).
- Backfill de notas existentes, job classificador, reescrita de registro.
- `CreatePrivateNote` como tool global: é nota de conversa, não memória de contato (design §4.8).
- Despromoção automática de nota promovida.

## 7. Critérios de aceite (rascunho)

### US1 — O Scout para de despejar notas no prompt

- O contexto de contato do v2 é montado por whitelist de campos; nenhuma nota entra por
  `to_llm_text`.
- Um contato com dezenas de notas produz contexto de tamanho estável, independente do histórico.
- O parágrafo de aviso sobre notas (`memory_notes_warning`) não existe no prompt v2 — não há o que
  avisar.

### US2 — Nota tipada na escrita, gate por origem na leitura

- Ao fim da conversa, cada nota gerada pelo Scout é persistida com `kind` (`fato` ou `episodio`),
  produzido na **mesma** chamada de LLM que já existia — sem chamada adicional.
- Só notas com `user_id IS NULL` **e** `kind: fato` entram no contexto do turno, limitadas às N mais
  recentes. `[A CONFIRMAR: valor de N — o design diz "top N por recência" sem fixar o número]`
- Uma nota `episodio` ("foi transferido para humano em 19/09") fica visível ao atendente no
  Chatwoot e **não** aparece no prompt.
- Uma nota escrita por atendente não aparece no prompt, qualquer que seja seu conteúdo.
- Notas anteriores a esta fase não aparecem no prompt (sem backfill), e nada quebra por causa disso.
- Editar a nota no Chatwoot muda o que o Scout lê; excluir a nota remove o atributo automaticamente.

### US3 — Promoção explícita de nota humana

- O atendente pode marcar uma nota sua como fato utilizável pelo Scout; a partir daí ela entra no
  contexto sob as mesmas regras de recência.
- A ação é opt-in, reversível e auditável (quem promoveu e quando).
- Sem promoção, o comportamento padrão permanece o da US2.
- `[A CONFIRMAR: superfície da ação — menu da nota no painel de contato do dashboard ou ação no
  super admin]`

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout_v2/..._spec.rb` (contexto de contato): ausência de notas no
  contexto quando não há `fato` do Scout; presença quando há; limite de recência.
- `custom/spec/services/custom/scout/contact_notes_service_spec.rb` (extensão): schema `{kind,
  content}` persistindo o atributo; uma única chamada de LLM.
- `custom/spec/models/...`: cascade de exclusão removendo o atributo.
- Verificação no playground: replay do cenário da Fase 32 (nota de handoff de conversa anterior
  presente) — o Scout segue o funil sem transferir; pedido genuíno de humano na conversa atual
  continua transferindo.

---

> **Nota de proveniência**: decomposto de `docs/kanban/scoutv2/design.md` §4.8 e §6 (Fase 3 + 6.6);
> o caso de produção que motiva a fase está documentado em
> `docs/kanban/ciclo 10/scout/32-contact-memory-handoff-pretext-guardrail/spec-preview.md`, com
> `Note#id` 43/52 e as conversas 44877/45006.
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
