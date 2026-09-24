# Revisão — ScoutV2 (design.md)

**Revisor:** avaliação de arquitetura sênior, com 3 subagentes despachados em paralelo
(auditoria Botpress, estado da arte externo, reúso/menor-impacto) + verificação direta de
código-fonte (v1, RubyLLM no container, ERP adapters, `Note` model).
**Data:** 2026-09-24
**Veredito geral:** **aprovar, com 1 item bloqueante antes da Fase 3 e 3 ajustes de conteúdo
antes de considerar o doc fechado.** O diagnóstico do v1 é factualmente correto em toda
alegação verificada. A adaptação do modelo Botpress é fiel ao ponto de citação verbatim
confirmada linha a linha. As 6 decisões técnicas centrais têm respaldo direto na literatura
2023-2025 (nenhuma contrariada). O caminho é de fato o de menor impacto nos subsistemas
periféricos (ERP, conhecimento, observabilidade) — mas superestima o custo de uma alternativa
incremental para a fatia *state-driven* do roteamento, e deixa uma lacuna real e não trivial no
ciclo de vida de `Note` que compromete a Fase 3 como está escrita.

---

## 1. Metodologia

- **Evidência do v1:** lidos diretamente `system_prompts_service.rb`, `response_auditor.rb`,
  `agent_runner.rb`, `funnel_section_builder.rb`, `opportunity_stage_transition_service.rb`,
  `base_tool.rb`, `contact_notes_service.rb`, `faq_generator_service.rb`,
  `search_knowledge_base.rb`, `scout_tool.rb`, `call_custom_api.rb`, `move_opportunity_stage.rb`,
  `handover_to_human.rb`, `handoff_service.rb`, `scout.rb`, `note.rb`, `notes_controller.rb`,
  `erp/base_adapter.rb`, `erp/adapter_factory.rb`, `erp_controller.rb`, `apps.yml`, e as specs
  `system_prompts_service_spec.rb` (completo, 650 linhas) e `faq_generator_service_spec.rb`
  (completo). `db/schema.rb` grepado para confirmar ausência de `engine`/tabelas novas.
- **Subagente `BotpressAudit`** (scout): confrontou §2 e §5 do design.md contra
  `/tmp/bp-llms-full.txt` (doc oficial Botpress, 43k linhas — expirou a meio da investigação;
  o subagente recuperou via fetch direto de `botpress.com/docs/*` e `unpkg.com/llmz@1.0.2/*`,
  `@botpress/adk@2.0.5`, `@botpress/runtime@2.0.5`) e o pacote `llmz@1.0.2` (substrato de
  execução público, MIT-adjacente).
- **Subagente `StateOfArtAudit`** (task, busca web): validou as 6 decisões centrais contra
  literatura externa 2023-2025 (Anthropic, OpenAI, Rasa, Parlant, papers arXiv, Letta/MemGPT,
  Zep, Mem0, práticas de chunking RAG).
- **Subagente `ReuseImpactAudit`** (scout): verificou reúso de infraestrutura do fork e avaliou
  se existe caminho incremental mais barato que o rewrite proposto.
- **Verificação cruzada própria:** subi o container `rails` (`docker compose up -d rails`) e li
  `ruby_llm-1.15.0/lib/ruby_llm/chat.rb` diretamente para arbitrar uma divergência entre o
  design.md e o `ReuseImpactAudit` sobre o mecanismo de re-injeção mid-turn (ver §5.1).

---

## 2. Diagnóstico do v1 — confirmado, sem correção material

Toda alegação verificável do §1 do design.md se sustentou na leitura direta do código:

| Alegação do design.md                                                                                                            | Verificação direta                                                                                                                                                                                                                                                                                                                                                                                   |
| -------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `system_prompts_service_spec.rb` só testa substring, não comportamento                                                           | **Confirmado 100%.** As 650 linhas da spec são inteiramente `expect(prompt).to include(...)` / `not_to include(...)`. Zero asserção sobre saída do modelo. Isso é sistêmico, não isolado: `response_auditor_spec.rb` também stuba os dois classificadores LLM (`instance_double`) em todo teste — nenhuma spec do v1 exercita um LLM real. O ponto do design.md em §7 é, se algo, **subestimado**.   |
| Regra "não faça perguntas ao transferir" escrita 3×, com comentário admitindo que o prompt estático "não é salient o suficiente" | **Confirmado literalmente.** `system_prompts_service.rb:185-189` tem esse comentário verbatim. `opportunity_stage_transition_service.rb:9-11` (`NO_QUESTION_CLOSING_INSTRUCTION`) e `base_tool.rb:62-73` (`scoped_confirmation_reminder`) replicam o mesmo padrão de reforço just-in-time, cada um com o mesmo raciocínio documentado em comentário.                                                 |
| Classificador de handoff aluncina em turno de múltipla escolha, 5/5 vezes                                                        | **Confirmado.** Comentário em `response_auditor.rb:47-57`, com contexto de produção detalhado (linha completa citada no código, não parafraseada).                                                                                                                                                                                                                                                   |
| `faq_generator_service.rb`: corte cego em 12.000 chars, 1 chamada por documento inteiro, não-reprodutível                        | **Confirmado, e a spec trava o comportamento sem testar a perda.** `MAX_CONTENT_LENGTH = 12_000` (linha 4), truncamento na linha 17, `temperature: 0.0` já setada (linhas 18-19) exatamente como citado. `faq_generator_service_spec.rb:70-79` **testa e afirma** o truncamento em 12.000 chars sem qualquer asserção sobre o conteúdo perdido — a spec documenta o bug como comportamento esperado. |
| `move_opportunity_stage` e `handover_to_human` são tools de mutação livre, sem escopo                                            | **Confirmado.** Ambos são `RubyLLM::Tool` chamáveis em qualquer turno, sem qualquer guarda de estado — `handover_to_human.rb:16-27` aceita `assignee_id`/`team_id`/`reason` livres a qualquer momento da conversa.                                                                                                                                                                                   |
| Pipeline de conhecimento, ERP adapters, observabilidade — mesmos objetos, sem mudança de contrato                                | **Confirmado** (ver §5, corroborado por leitura direta de `erp/base_adapter.rb`, `erp/adapter_factory.rb`, `search_knowledge_base.rb`, `apps.yml:341-350`).                                                                                                                                                                                                                                          |

**Nit de citação (sem impacto na tese):** `apps.yml:341-348` no apêndice do design.md aponta
para `category` + `visible_properties`; na prática `category: erp` está na linha 348 e
`visible_properties` na 350 — desvio de 2 linhas, não um erro de conteúdo. Da mesma forma,
`erp_controller.rb:20` hoje resolve por `h.app_id == 'younus' || h.app&.params&.dig(:category)
== 'erp'` — é um **OR** vendor-ou-categoria (compatibilidade retroativa), não puramente por
categoria como a prosa do §4.5 sugere. Não invalida a tese de reúso (o padrão de registro por
categoria já existe e é o que importa para `CapabilityRegistry`), mas a frase deveria dizer
"já resolve por categoria, mantendo um fallback por vendor" em vez de "em vez de por vendor".

---

## 3. Fidelidade ao modelo Botpress — confirmada, com verbatim

Veredito do `BotpressAudit` (relatório completo em `agent://BotpressAudit`): **toda** alegação
semântica e mecânica do §2 do design.md foi confirmada, várias delas verbatim:

- Distinção Instructions/Playbook, regra de corte, escopo de tools por playbook ativa,
  Escalation como camada própria, flow test multi-turno, "conectar integração não basta" —
  todas **confirmadas com citação verbatim** em `botpress.com/docs/viber/build/behavior` (o
  subagente re-obteve a doc ao vivo depois que o cache local `/tmp/bp-llms-full.txt` expirou a
  meio da investigação).
- Mecanismo `llmz@1.0.2`: `_refreshIterationParameters` recalculando `instructions`/`tools`/
  `exits`/`model`/`temperature` via `ValueOrGetter<T,I>` a cada iteração — **confirmado
  verbatim** em `custom-client-C-WXvLD9.js:1428-1440` e `DOCS.md:149`. Prompt com slot único de
  instrução (`native-*.js:157-195`), `protocol` condicional a `hasExits`/`components.size`
  (`:78-120`), `Exit` com schema validado e hook `onExit` que pode vetar a saída
  (`exit.d.ts:60-188`), `ContextTokens` com categorias `framework/instructions/tools/protocol/
  iterations` (`context.d.ts:20-35`) — **tudo confirmado**.
- Ausência de `Playbook` em `@botpress/adk@2.0.5` e `@botpress/runtime@2.0.5` — **confirmada**
  por inspeção direta dos `.d.ts` públicos: nenhum dos dois pacotes exporta ou define
  `Playbook`; `@botpress/runtime` declara `llmz` como dependência e expõe apenas primitivas de
  `Workflow`/`Autonomous`, não Playbooks (que são proprietárias do Botpress Cloud).
- Tabela de divergência (§5): **confirmada e tecnicamente justificada** — em particular, a
  linha de roteamento está correta: Botpress de fato roteia por triagem LLM conversacional
  ("Intent Triage" via trigger textual), e a divergência para `when_state` determinístico em
  Ruby é lida pelo subagente como "resolve exatamente o modo de falha estocástico que
  paralisou o v1".

**Gaps que o design.md não trata, levantados pelo subagente:**

1. `llmz` tem um **teto defensivo de 100 tools por turno** (`custom-client-C-WXvLD9.js:1440`,
   lança `InvalidConfigurationError` acima disso). O design.md não define um limite ou teste de
   cardinalidade equivalente para o total de tools injetadas (globais + da playbook ativa +
   capabilities). Baixa urgência dado o catálogo atual pequeno, mas deveria ser uma invariante
   explícita validada no boot (mesma seção de §4.4 que já valida referência quebrada), não uma
   suposição implícita.
2. `llmz` reserva ~10% da janela de contexto para saída e compacta o histórico a 85% de uso
   (`DOCS.md:200-240`). O design.md não define política de orçamento/truncamento de histórico
   para conversas longas — a observabilidade (§4.9) mede o que aconteceu, não impõe um teto.
   Isso é uma lacuna real para conversas de handoff tardio ou reagendamento com muita
   ida-e-volta.
3. Semântica de fim de turno implícito (`ListenExit`) não tem contrato formal de detecção no
   `TurnRunner` — o design.md descreve o comportamento esperado (§4.6) mas não como o runner
   distingue "sem exit porque é o caso normal" de "sem exit porque o modelo falhou em chamar
   um exit devido". Ver também §5 deste documento (achado do `ReuseImpactAudit` sobre
   `ActionClassifierService`).
4. Nit: `llmz@1.0.2/package.json` declara licença **ISC**, não MIT como o design.md cita em
   §2.2 e no apêndice. Corrigir a atribuição.

---

## 4. Alinhamento com estado da arte externo — suportado, com 2 ressalvas de enquadramento

Veredito do `StateOfArtAudit` (relatório completo em `agent://StateOfArtAudit/report_markdown`):
**nenhuma das 6 decisões centrais é contrariada pela literatura 2023-2025**; todas convergem
independentemente com fontes primárias de peso:

| Decisão | Veredito | Fonte principal |
|---|---|---|
| 1 — roteamento determinístico com fallback textual | Suportado | Anthropic *Building Effective Agents* (routing pode ser LLM **ou** classificador tradicional); Rasa `RulePolicy` (prioridade determinística vence sobre política estatística) |
| 3/12 — tools escopadas por playbook; mutação vira exit, não tool | Suportado | IBM/arXiv:2504.00914 (tools distratoras derrubam acurácia 1-8pp); guidance oficial da OpenAI para function calling (bind só o subconjunto relevante por turno); Anthropic "poka-yoke" de tools |
| 9 — remoção do auditor pós-hoc | Suportado com ressalva | Huang et al., ICLR 2024 (arXiv:2310.01798) e Stechly et al. (arXiv:2402.08115): auto-crítica sem oráculo externo degrada, não melhora |
| 10 — memória fato/episódio, só fato no prompt | Suportado, melhor evidenciado dos 6 | Letta/MemGPT (Core vs Recall/Archival Memory), Zep (arXiv:2501.13956, subgrafo episódico vs semântico), Mem0 |
| 11 — chunking determinístico com overlap | Suportado | Práticas de RAG em produção convergem em chunking fixo+overlap como baseline reprodutível; não-reprodutibilidade de extração LLM em `temperature=0` é fenômeno documentado (não-associatividade de kernels paralelos) |
| §4.2 — recomputação por iteração | Suportado, é o mais nomeado externamente | Anthropic *"context engineering"* como termo do setor 2024-2025; mesma lógica aplicada por Letta ao "paging" de memória |

**Duas ressalvas de enquadramento que o design.md deveria incorporar textualmente:**

1. **Decisão 9 está fraseada mais forte do que a literatura sustenta.** A literatura endossa
   matar auto-crítica síncrona do mesmo modelo sem *ground truth* externo — não endossa "zero
   guardrail" como princípio geral. A prática recomendada é substituir por **verificação
   determinística barata** (validação de schema, regra/regex, gate binário) e não por nada. O
   design.md já tem, estruturalmente, essa substituição: a remoção das tools de mutação livre
   (Decisão 3/12) **é** o guardrail determinístico que ocupa o lugar do auditor — mas §3.9 do
   design.md não faz essa ligação explícita, e a Tabela do §4.6 lê-se como "removemos
   verificação porque a causa some", quando o correto é "trocamos verificação estocástica por
   verificação estrutural (payload de exit validado em Ruby)". Recomendo adicionar uma frase
   cruzando as Decisões 3/12 e 9 explicitamente.
2. **"Typed exit" não tem precedente nomeado na literatura externa** — é síntese legítima de
   princípios estabelecidos (tool scoping + poka-yoke + gating de efeito colateral), mas o
   design.md não deveria (e não faz, ao reler com cuidado — está ok) apresentá-lo como
   replicando um padrão de mercado com nome próprio. Mantém-se como decisão de engenharia do
   fork, o que é o enquadramento correto.

Achado adicional de calibração: o paper do IBM sobre degradação por tools distratoras usa
conjuntos em escala BFCL (dezenas de tools); o catálogo pré-refactor do v1 tem **7 tools**
(`agent_runner.rb:145-155`, confirmado por leitura direta). A direção do efeito (menos tools
simultâneas → menos erro de seleção) se sustenta, mas a magnitude citada no paper não deve ser
importada como "essa é a redução esperada aqui" — o design.md não faz essa extrapolação
numérica, então isso é apenas uma nota de cautela para comunicação futura do resultado, não uma
correção ao doc.

---

## 5. Caminho de menor impacto — parcialmente correto; uma premissa técnica do subagente foi corrigida por mim

Veredito do `ReuseImpactAudit` (relatório completo em `agent://ReuseImpactAudit`): confirma que
os subsistemas periféricos pesados do fork (ERP adapters, pipeline de conhecimento com
pgvector, instrumentação OTel/Langfuse, gate de audiência, quota, debounce, follow-up,
estimativa de valor, classificador de referral, continuidade de oportunidade) são **reutilizados
sem retrabalho**, com citação de arquivo:linha para cada um — nenhuma dessas alegações do
design.md precisou de correção.

### 5.1 A alegação central do subagente precisa de correção — verificada por mim no gem real

O `ReuseImpactAudit` concluiu que "RubyLLM não possui hook de getters por iteração" e que,
portanto, o scoping do ScoutV2 seria "puramente por turno", igualável por condicionais dentro
do `AgentRunner`/`SystemPromptsService` atuais sem qualquer arquitetura nova. **Subi o container
`rails` e li `ruby_llm-1.15.0/lib/ruby_llm/chat.rb` diretamente para arbitrar isso** — a alegação
do subagente está **factualmente incorreta** no ponto que mais importa:

```ruby
# chat.rb:156-179 (complete)
def complete(&)
  response = @provider.complete(messages, tools: @tools, ...)
  ...
  handle_tool_calls(response, &) if response.tool_call?
end

# chat.rb:275-289 (handle_tool_calls)
def handle_tool_calls(response, &)
  halt_result = nil
  response.tool_calls.each_value do |tool_call|
    result = execute_tool tool_call
    ...
  end
  halt_result || complete(&)   # <- reentra em complete, relendo @tools/@messages ATUAIS
end
```

`complete` passa `tools: @tools` — a variável de instância, não uma cópia — e
`handle_tool_calls` termina reentrando em `complete` recursivamente. Como `with_tool` escreve
em `@tools[...]` e `with_instructions` sobrescreve a mensagem de sistema no mesmo array
`@messages`, **qualquer tool que segure a referência do `chat` pode alterar tools/instruções
no meio do `chat.ask`, e a chamada recursiva seguinte já parte do estado novo.** Isso é
exatamente o que o design.md já afirma e cita em §4.2 (com os números de linha corretos do
gem) — o `ReuseImpactAudit`, ao concluir o oposto, não confrontou o gem real, só inferiu a
partir da ausência de um `getter` explícito nomeado como no `llmz`.

**Consequência para o veredito de menor-impacto:** isso divide a questão em duas partes que o
subagente tratou como uma só:

- **Para o roteamento *state-driven*** (quando `when_state` já resolve a playbook antes do
  turno começar — a maioria dos casos do primeiro corte, incluindo `identificacao`,
  `qualificacao`, `agendamento`): o `ReuseImpactAudit` está certo. Isso **poderia** ser feito
  com condicionais dentro de `SystemPromptsService#guardrails_section` e
  `AgentRunner#build_tools` (rascunho do próprio subagente: ~200-300 linhas, zero tabela nova,
  zero YAML, zero DSL de predicado). O design.md não discute essa alternativa mais barata para
  esse subconjunto específico, e deveria — nem que seja para documentar por que foi descartada
  (testabilidade determinística sem LLM e contenção de churn, que são reais, mas merecem estar
  no corpo do doc, não só inferíveis).
- **Para o roteamento *trigger-driven mid-turn*** (§4.2, "nenhuma [playbook] casa e sem ativa →
  só índice; o modelo abre por trigger" — o caso em que a intenção só fica clara depois que a
  conversa já começou o turno, ex.: "e sobre marcar horário?"): a alternativa incremental do
  subagente **não cobre esse caso** sem reinventar, dentro do `AgentRunner` atual, o mesmo
  mecanismo de tool-que-muta-`@tools`/`@messages` mid-chamada que o design.md já propõe como
  `open_playbook`. Não há como decidir "abrir uma playbook e já ativar suas tools no mesmo
  turno" com um `build_tools` calculado uma vez antes do `chat.ask` — isso exigiria adiar a
  ativação para o turno seguinte, que é exatamente o "turno morto" que o design.md já
  rejeita em §4.2.

**Veredito líquido:** a arquitetura nova (playbook/router/capability/`TurnRunner`) **não é
estritamente necessária só para resolver o scoping state-driven** — mas **é** necessária (ou
algo estruturalmente equivalente a ela) para o caso trigger-driven mid-turn, que é parte real
do escopo do primeiro corte (`duvida_comercial`, `pausa`, `fora_de_prospeccao` — todas ativadas
só por trigger, sem `when_state`, conforme a tabela da Fase 1 em §6 do design.md). Dado que o
mecanismo mid-turn já é necessário para essas 3 das 6 playbooks do corte 1, construir o mesmo
roteador para as demais (em vez de manter dois mecanismos de ativação paralelos — condicionais
para state-driven, tool-based para trigger-driven) é a decisão de engenharia mais defensável,
não um excesso. **Recomendo que o design.md adicione esse raciocínio explicitamente** — hoje
ele afirma a necessidade da arquitetura nova sem confrontar a alternativa incremental
diretamente, o que deixa a decisão lendo como não-examinada quando na verdade, com essa análise,
ela se sustenta.

### 5.2 Achado bloqueante — ciclo de vida de `Note` não tem gancho, contradiz "sem tocar note.rb"

Confirmado por leitura direta minha e pelo `ReuseImpactAudit`:

```ruby
# app/models/note.rb — completo, 36 linhas
class Note < ApplicationRecord
  before_validation :ensure_account_id
  validates :content, presence: true
  validates :account_id, presence: true
  validates :contact_id, presence: true
  belongs_to :account
  belongs_to :contact
  belongs_to :user, optional: true
  scope :latest, -> { order(created_at: :desc) }
  private
  def ensure_account_id
    self.account_id = contact&.account_id
  end
end
```

```ruby
# app/controllers/api/v1/accounts/contacts/notes_controller.rb
def create
  @note = @contact.notes.create!(note_params)
end
def update
  @note.update(note_params)
end
```

**Zero callbacks, zero `after_commit`, zero evento emitido.** O design.md §4.8 afirma: *"Ao
criar ou editar uma nota, um job assíncrono grava `fato` ou `episodio`"* e lista como decisão
explícita não tocar `app/models/note.rb` (upstream, por `AGENTS.md`). Essas duas afirmações são
**incompatíveis como o doc está escrito hoje**: sem um gancho em algum lugar, o job assíncrono
de classificação nunca dispara para notas criadas ou editadas por atendente humano via UI —
que é precisamente o caso que a Decisão 10 existe para resolver (nota humana "cliente chato,
manda pro humano" sendo lida como instrução).

Isso **não exige** violar a regra de não editar arquivos upstream diretamente: o próprio
`AGENTS.md` (seção "Enterprise Edition Notes") já estabelece o padrão do fork para exatamente
esse caso — `prepend_mod_with`/`include_mod_with` via um módulo em `custom/app/models/`. A
correção natural, compatível com a convenção já em uso no repositório:

```ruby
# custom/app/models/custom/note.rb (novo, ficheiro do fork, não upstream)
module Custom::Note
  extend ActiveSupport::Concern
  included do
    after_commit :classify_scout_note_attribute!
  end
  private
  def classify_scout_note_attribute!
    Custom::ScoutV2::ClassifyNoteJob.perform_later(id)
  end
end
```

com `Note.include Custom::Note` no ponto de extensão apropriado — o mesmo mecanismo que o
`AGENTS.md` já pede para qualquer extensão de comportamento OSS. **Este é o único item que
considero bloqueante**: a Fase 3 não é implementável como o design.md a descreve sem resolver
esse ponto, e a solução está a um parágrafo de distância usando um padrão que o próprio repo já
convenciona. Recomendo adicionar esse parágrafo ao §4.8 antes de aprovar a Fase 3 para
execução.

### 5.3 Achado menor — "v1 intocado" precisa de escopo mais preciso

Confirmado: para o `engine: v2` da Fase 5 funcionar, é necessário (a) coluna nova em
`ichatr_scouts` e um `enum engine:` em `custom/app/models/scout.rb`, e (b) um branch de
despacho em `process_message_job.rb` decidindo entre `AgentRunner` (v1) e `TurnRunner` (v2). A
Decisão 5 ("v1 intocado e depreciado depois") é verdadeira para as *classes de comportamento*
(`AgentRunner`, `ResponseAuditor`, `SystemPromptsService` seguem existindo sem edição), mas
tecnicamente falsa para "zero diff no repo" — `Scout` e `ProcessMessageJob` recebem um branch de
roteamento de engine. Isso é esperado e barato (qualquer estratégia de convivência precisaria
disso), mas a frase no doc deveria dizer "os serviços de comportamento do v1 seguem intocados"
em vez de "v1 intocado" tout court, para não gerar expectativa de zero diff.

### 5.4 Achado real, já mitigado em parte no §8 — remoção do `ActionClassifierService` sem rede determinística

O `ReuseImpactAudit` levanta um modo de falha concreto: o cliente diz "não quero robô, me
passe para uma pessoa"; o modelo aluciona uma resposta textual tipo "entendido, vou chamar
alguém" **sem invocar** `exit_handoff`; a conversa fica presa no bot porque não há mais nenhum
classificador pós-hoc para pegar esse caso — o v1 criou o `ActionClassifierService`
exatamente para essa classe de erro.

O design.md já antecipa essa categoria de risco em §8 ("Remover o auditor expõe erro que ele
cobria" → mitigação: instrumentação desde a Fase 1, reintrodução cirúrgica na Fase 6.7 "com
evidência"). Isso não é um gap não-tratado, mas a mitigação é **puramente reativa**: exige que
o caso ocorra em produção e apareça no Langfuse antes de qualquer correção. Para esse caso
específico — o modelo promete verbalmente uma ação de handoff sem chamar a tool — existe uma
rede **preventiva e barata** que não exige reintroduzir o classificador estocástico: validar,
no `ExitHandler` ou num callback `after_message` do `TurnRunner`, se o texto final contém
marcadores fortes de compromisso de transferência (ex.: menções a "atendente"/"humano" em
voz de primeira pessoa do assistente) sem um exit correspondente ter sido chamado no mesmo
turno, e registrar isso como métrica de alerta antes de virar reclamação de cliente — não como
auditor bloqueante, apenas como sinal early-warning que abastece a decisão da Fase 6.7 com
evidência mais cedo. Recomendo adicionar essa métrica ao §4.9 (Observabilidade) como parte do
corte inicial, não como algo que espera a Fase 6.7 para ser sequer instrumentado.

---

## 6. Recomendações concretas antes de fechar o design.md

1. **Bloqueante:** adicionar ao §4.8 o mecanismo de gancho para classificação de notas humanas
   (`prepend_mod_with`/módulo `custom/app/models/custom/note.rb` com `after_commit`, ou job de
   varredura periódica como alternativa mais fraca) — sem isso a Fase 3 não é implementável como
   escrita.
2. Adicionar ao §3 (Decisão 9) ou §4.6 uma frase explícita ligando a remoção do auditor à
   remoção das tools de mutação livre como o guardrail determinístico substituto — hoje a seção
   lê como "removemos verificação porque a causa some" quando o correto e mais defensável é
   "trocamos verificação estocástica por verificação estrutural".
3. Adicionar uma subseção curta de "alternativas consideradas" em §4 confrontando o caminho
   incremental (condicionais em `SystemPromptsService`/`build_tools`) explicitamente, explicando
   por que ele cobre o roteamento state-driven mas não o trigger-driven mid-turn — a análise do
   §5.1 deste documento pode ser reaproveitada quase diretamente.
4. Corrigir a licença de `llmz` no apêndice (ISC, não MIT) e o offset de linha de
   `apps.yml:341-348` → `348 (category), 350 (visible_properties)`.
5. Adicionar ao §4.4 (validação no boot) um teto de cardinalidade para o total de tools
   injetadas por turno (paralelo ao guard de 100 tools do `llmz`), e ao §4.2 ou §8 (riscos) uma
   política mínima de orçamento/truncamento de histórico para conversas longas — ambos
   ausentes hoje e ambos têm precedente direto no próprio `llmz`.
6. Tightening de linguagem: trocar "v1 intocado" por "serviços de comportamento do v1 seguem
   intocados" na Decisão 5, dado que `Scout` e `ProcessMessageJob` recebem um branch de
   despacho de engine.
7. Adicionar ao §4.9 uma métrica early-warning para "compromisso verbal de handoff sem exit
   correspondente no turno" desde o corte inicial, em vez de esperar a Fase 6.7 para
   instrumentar o sinal que justificaria reintroduzir verificação (ver §5.4).

Nenhuma dessas recomendações muda a direção arquitetural. Os itens 2-7 são ajustes de precisão
textual e observabilidade; o item 1 é o único que bloqueia a Fase 3 como está escrita.

---

## 7. Veredito final

O ScoutV2 resolve o problema estrutural correto — ausência de escopo, não redação de prompt —
com um mecanismo (Instructions sempre-on + Playbook situacional + tools/exits escopados por
turno) que é uma adaptação fiel e tecnicamente correta do modelo Botpress, divergindo
deliberadamente só onde a divergência é justificada por evidência própria do fork (roteamento
determinístico em vez de triagem LLM, dado o histórico documentado de alucinação do
classificador v1). As seis decisões centrais têm respaldo direto e não contrariado na literatura
de arquitetura de agentes 2023-2025. O reúso de infraestrutura periférica do fork (ERP,
conhecimento, observabilidade, gates orthogonais) é real e foi verificado arquivo por arquivo,
não apenas alegado. A crítica de "existe caminho mais barato" é parcialmente procedente — para
o subconjunto state-driven do roteamento — mas não subtrai a necessidade do mecanismo novo para
o subconjunto trigger-driven, que é parte real do escopo da Fase 1. O único ponto que impede
aprovação incondicional é a lacuna de gancho no ciclo de vida de `Note`, que tem solução
direta e alinhada à convenção já estabelecida no `AGENTS.md` do próprio repositório.
</parameter>
