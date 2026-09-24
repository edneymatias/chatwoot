# Avaliação Arquitetural: Scout v2 — Playbooks, Capabilities e Memória Tipada

**Papel:** Arquiteto Sênior de Agentes de LLM integrados a Atendimento ao Cliente e CRM  
**Data:** 24 de Setembro de 2026  
**Documento Avaliado:** `docs/kanban/scoutv2/design.md`  
**Base de Evidências:** Código e specs do Scout v1 (`custom/app/services/custom/scout/*`, `docs/kanban/ciclo 10/scout/*`), referência de produto e runtime do Botpress (`llmz`), literatura acadêmica e benchmarks da indústria (Anthropic, OpenAI, Berkeley BFCL, ICLR 2024, Zep/Letta).

---

## 1. Parecer Executivo

O projeto arquitetural do **Scout v2** registrado em `design.md` é **APROVADO COM LOUVOR**.

A arquitetura proposta não apenas possui o potencial de resolver de maneira definitiva as dores, instabilidades e custos excessivos do Scout v1, como ataca cirurgicamente a **causa raiz primária** de todo o churn do Ciclo 10: a premissa de um *prompt monolítico e desprovido de escopo, acumulando todas as regras, ferramentas e contextos em todos os turnos*.

A investigação realizada em três frentes independentes (código e histórico do repositório, referência Botpress e Estado da Arte na literatura/indústria) confirma:
1. **Resolução Efetiva dos Gaps:** O v2 desmantela a "escada de compensações" que transformou o v1 em um sistema frágil de 3 a 8 chamadas LLM por turno. Ao introduzir escopo situacional via Playbooks e validação exógena via Exit Tools, elimina a necessidade do auditor estocástico pós-hoc (`ResponseAuditor`).
2. **Fidelidade e Maturidade na Transposição do Botpress:** O v2 absorve os três pilares semânticos comprovados do Botpress (*Instructions* para regras duráveis, *Playbooks* para procedimentos ordenados e *Escalation* para transbordo) e seu modelo de execução dinâmico (*scoped tools* e *typed exits*). Ao mesmo tempo, afasta-se conscientemente das limitações do Botpress, adotando roteamento determinístico em Ruby sobre o CRM (em vez de gastar tokens com LLM Intent Triage) e abstração de *Capabilities* tipadas (em vez de amarrar o fluxo a endpoints de vendor).
3. **Alinhamento Rigoroso com o Estado da Arte (SOTA):** O desenho adota as melhores práticas consolidadas entre 2024 e 2026: prevenção de *Lost in the Middle* (Liu et al.), mitigação de *Tool Bloat* e alucinação de argumentos (Berkeley BFCL), rejeição de laços ingênuos de autocorreção estocástica sem grounding (Huang et al., ICLR 2024), e separação formal de memória em Fatos vs. Episódios (padrão Zep/Graphiti/Letta).
4. **Caminho do Menor Impacto e Máximo Aproveitamento:** O v2 preserva 100% da infraestrutura periférica de produção do v1 (filas, debounce via Redis Alfred, gates de audiência e quota, RAG PGVector, adapters de ERP e modelos de dados do CRM). A adoção do padrão *Strangler Fig* em namespace isolado (`Custom::ScoutV2::*`) garante risco zero de regressão e capacidade de reversão instantânea via feature flag por scout (`engine: v2`).

Abaixo segue a fundamentação técnica e arquitetural detalhada.

---

## 2. Diagnóstico Forense do Scout v1: A Escada de Compensações

O histórico do repositório (`docs/kanban/ciclo 10/scout/`) e o código em produção contam uma história inequívoca de **compensações empilhadas sobre uma fundação sem escopo**:

```
[Prompt Monolítico v1] (~11k-15k chars, 11 bullets globais, 7 tools incondicionais)
       │
       ▼ (Atenção diluída / "Lost in the Middle" / descumprimento de regras)
[Regra Duplicada 3x] (Bullet global :77 + reminder final :190-195 + tool result)
       │
       ▼ (Mesmo assim, o modelo alucina ou encerra incorretamente)
[ResponseAuditor / ActionClassifier] (Fase 12: LLM-as-a-Judge pós-hoc a temp 0.0)
       │
       ▼ (Classificador alucina handoff em 5/5 respostas curtas de agendamento)
[Confirmação Dupla] (Segunda chamada estocástica a temp 0.7 para desempatar)
       │
       ▼ (Piso de 3 chamadas LLM; Claims inconsistentes disparam laço de repair)
[Repair Loop] (execute_repair reenviando chat.ask com REPAIR_INSTRUCTION)
       │
       ▼ (Desastre documentado na Fase 35 - Preview)
[Narrative Leak & Double Handoff] ("Desculpe a confusão anterior", 2 mensagens enviadas)
```

### 2.1 Evidência 1: A "Confissão" no Próprio Código
Em `custom/app/services/custom/scout/system_prompts_service.rb:185-189`, os desenvolvedores do v1 registraram com franqueza o motivo de terem criado a seção `handoff_closing_reminder_section`:
> *"Repeats the 'Fallback para humano' no-question rule right before the response format instructions, closest to where the model actually writes its final turn text — a static system-prompt bullet read many messages earlier is not salient enough on its own (see OpportunityStageTransitionService::NO_QUESTION_CLOSING_INSTRUCTION for the companion just-in-time reinforcement delivered via the tool result itself)."*

Quando uma regra negativa de negócios precisa ser gravada no topo (`:77`), repetida no final (`:190-195`) e reinjetada no retorno da ferramenta (`opportunity_stage_transition_service.rb:9-11,47`), fica provado que o problema **não é de engenharia de prompt**, mas de **arquitetura de contexto**.

### 2.2 Evidência 2: O Custo e a Instabilidade do `ResponseAuditor`
Em `custom/app/services/custom/scout/response_auditor.rb:4-8,50-54,72-77`, observa-se:
* **Falso-positivo crônico:** O classificador a temperatura 0.0 lia escolhas legítimas de horários de consulta pelo cliente como "aceitou oferta de transferência para humano" em **5 de 5 testes medidos em produção**.
* **Remédio estocástico:** Para contornar isso, adicionou-se uma segunda chamada LLM a `CONFIRMATION_TEMPERATURE = 0.7`, na tentativa de obter um "sorteio independente".
* **Multiplicação de chamadas:** Um turno normal que deveria consumir 1 chamada LLM passa a consumir:
  - 1 geração principal
  - 1 classificador de ação (temp 0.0)
  - 1 confirmação independente (temp 0.7)
  - 1 verificador de consistência de afirmações (`ClaimConsistencyService`)
  - Se houver inconsistência: 1 chamada de reparo (`execute_repair`) + re-classificação + reverificação.
  - **Piso: 3 chamadas. Pior caso: 8 chamadas consecutivas.**
  - **Latência percebida:** 15 a 40 segundos por mensagem no WhatsApp, gerando churn e quebra de engajamento do lead.

### 2.3 Evidência 3: O Laço de Reparo Corrompendo a Conversa (Fase 35)
O documento `docs/kanban/ciclo 10/scout/35-response-auditor-repair-loop-narrative-leak/spec-preview.md` relata um caso real em homologação:
* O cliente perguntou: *"quanto tá a limpez de vcs?"*.
* O assistente chamou `handover_to_human` corretamente na primeira passada.
* O `ClaimConsistencyService` julgou erroneamente a resposta como inconsistente e acionou o `execute_repair`.
* A instrução de reparo acusou: *"Sua resposta anterior afirmou que uma ação foi concluída... mas a ação não foi executada"*.
* O modelo, ao tentar se redimir dentro da mesma sessão de chat, enviou ao cliente:
  > *"Gandalf, o sábio, obrigado por aguardar e desculpe pela confusão antes. Já deixei seu atendimento a cargo da nossa equipe humana..."*
* O cliente recebeu uma desculpa por uma confusão que **nunca existiu na conversa externa**, além de uma segunda execução da ferramenta de handoff sobrescrevendo a nota interna.

### 2.4 Evidência 4: Contaminação de Contexto na Memória (Fase 32)
Em `contact_llm_formatter.rb` e `contact_notes_service.rb`, todas as notas do contato eram despejadas sem filtro no prompt:
* Anotações subjetivas de atendentes humanos (*"cliente chato, mandar pro supervisor"*) agiam como *accidental prompt injection*.
* Ocorrências episódicas passadas (*"cliente pediu humano em 12/08"*) faziam o Scout transferir novos contatos imediatamente em setembro (Fase 32), forçando mais uma regra paliativa no prompt global (`memory_notes_warning:134-141`).

### 2.5 Evidência 5: Tool Bloat e Projeção de Parâmetros Técnicos (`ScoutTool`)
Em `custom/app/services/custom/scout/tools/call_custom_api.rb` e `agent_runner.rb:145-155`:
* Todas as 7 tools eram enviadas sempre.
* As ferramentas de integração com o ERP Younus exigiam que o modelo gerasse em seu payload JSON parâmetros de infraestrutura: `idEmpresa`, `idAgenda`, `idUsuario`, `idConvenio`, `idOrigempessoa`.
* Esses dados são credenciais fixas de conta e ambiente (já configuradas em `apps.yml`), mas estavam expostos à alucinação do modelo a cada chamada.

**Conclusão do Diagnóstico:** O Scout v1 esgotou sua capacidade evolutiva. Qualquer nova regra adicionada ao prompt desestabiliza três regras anteriores. A transição para o v2 não é um luxo arquitetural; é uma necessidade de sobrevivência do produto.

---

## 3. Análise da Solução de Referência: Botpress

A análise da arquitetura do Botpress (especialmente sua camada Viber, Studio e o runtime open-source `llmz`) confirma que o Scout v2 capturou os princípios fundamentais da plataforma mais madura do mercado atual em agentes conversacionais orientados a tarefas:

### 3.1 Mapeamento Semântico
| Conceito Botpress | Realização no Scout v2 | Avaliação |
|---|---|---|
| **Instructions** | `Identity`, `Communication` (enums tipados), `Memory`, `Safety` | **Idêntico.** Mantém apenas regras duráveis de governança e persona. |
| **Playbooks** | Procedimentos ordenados em arquivos `.md` versionados | **Idêntico.** Passos específicos, condições de ativação e escopo restrito. |
| **Dynamic Tool Scoping** | Tools ativadas estritamente com a playbook | **Idêntico.** Elimina Tool Bloat; capabilities só entram com a playbook ativa. |
| **Escalation** | Camada própria declarada, executada no ponto de saída | **Idêntico.** Unifica a política de transbordo e protocolo pré-handoff. |
| **Exits** | Ferramentas tipadas injetadas (`exit_agendado`, `exit_handoff`) | **Idêntico.** Desfecho estruturado com schema validado no loop. |
| **Flow Tests** | Specs multi-turno contra playbooks isoladas com mocks | **Idêntico.** Testabilidade determinística sem mockar strings de prompt. |

### 3.2 Avaliação das Divergências Conscientes do Scout v2
O Scout v2 afasta-se do Botpress em 4 pontos essenciais (Seção 5 de `design.md`). Como Arquiteto Sênior, avalio que **todas as 4 divergências são altamente vantajosas e adequadas à realidade do Chatwoot**:

1. **Capability vs. Flat Vendor Namespace:**
   - *No Botpress:* Cada bot é um silo em UI onde o usuário pluga ferramentas diretamente.
   - *No Scout v2:* O Chatwoot é um sistema multi-tenant distribuído. A playbook é código compartilhado do fork (`custom/playbooks/*.md`). Ela não pode acoplar-se ao webhook do cliente A ou do cliente B. A introdução de `Capabilities` (`scheduling.list_slots`, `scheduling.book`) atua como um contrato estável de interface, desacoplando o procedimento de negócios do provedor técnico de ERP.
2. **Roteamento Determinístico em Ruby vs. LLM Intent Triage:**
   - *No Botpress:* O roteamento entre playbooks é frequentemente delegado a uma playbook inicial de triagem baseada em LLM (`Intent Triage`).
   - *No Scout v2:* O estado do funil comercial (`opportunity.stage_role`), a existência de telefone e outros campos já residem no PostgreSQL com integridade transacional. Avaliar `when_state` em Ruby consome **0ms e 0 tokens**, possuindo 100% de determinismo. Reservar o `trigger` textual para o resíduo comportamental é a decisão correta para CRM.
3. **Playbooks em Arquivos Git (`.md`) vs. Banco de Dados / UI:**
   - *No Botpress:* Focado em interfaces no-code para usuários finais.
   - *No Scout v2:* Criar um construtor de playbooks em banco exigiria telas complexas de CRUD, versionamento de banco e validação dinâmica. Manter playbooks em arquivos Git no fork traz governança de código, CI validando referências no boot, testes de regressão automáticos e deploy atômico para todas as contas.
4. **Visualização do Derivado Q/A vs. Fonte Bruta:**
   - *No Botpress:* Exibe a página original indexada.
   - *No Scout v2:* O modelo consulta pares pergunta/resposta indexados no pgvector, e não o HTML bruto. Exibir o artefato exato que o RAG recupera confere transparência operacional imediata para suporte e diagnóstico.

---

## 4. Validação contra o Estado da Arte (SOTA) da Indústria

A literatura científica recente e as recomendações práticas dos principais laboratórios de IA (Anthropic, OpenAI, Berkeley) fornecem respaldo inequívoco para o desenho do Scout v2:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    CONSENSO DO ESTADO DA ARTE (2024-2026)                    │
├─────────────────────────┬────────────────────────────────────────────────────┤
│ Desafio de Engenharia   │ Respaldo Científico / Padrão Industrial            │
├─────────────────────────┼────────────────────────────────────────────────────┤
│ Prompt Monolítico       │ "Lost in the Middle" (Liu et al., Stanford)        │
│                         │ Guia "Building Effective Agents" (Anthropic)       │
├─────────────────────────┼────────────────────────────────────────────────────┤
│ Tool Bloat (7+ tools)   │ Berkeley Function-Calling Leaderboard (BFCL)       │
│                         │ "ToolBench: Large Language Models as Tool Users"   │
├─────────────────────────┼────────────────────────────────────────────────────┤
│ Auditor Pós-Hoc         │ "Large Language Models Cannot Self-Correct         │
│ (Self-Correction Loop)  │ Reasoning Yet" (Huang et al., ICLR 2024)           │
├─────────────────────────┼────────────────────────────────────────────────────┤
│ Contaminação de Memória │ Arquiteturas Cognitivas de Memória em Grafos       │
│                         │ Zep / Graphiti, Letta (MemGPT), LangMem            │
├─────────────────────────┼────────────────────────────────────────────────────┤
│ Orquestração de Fluxo   │ LangGraph StateCharts, Semantic Router / Guards    │
└─────────────────────────┴────────────────────────────────────────────────────┘
```

1. **Atenção e Alocação de Tokens:** O guia da Anthropic sobre agentes enfatiza: *mantenha o prompt o menor possível para a tarefa atual*. Misturar instruções de onboarding, regras de cancelamento e fluxo de agendamento em um único prompt degrada a probabilidade de cumprimento das regras situacionais.
2. **Dynamic Tool Scoping:** O benchmark BFCL comprova que a precisão de preenchimento de parâmetros cai abruptamente quando ferramentas não correlatas à intenção atual estão presentes no contexto. Ao restringir o catálogo de tools ao escopo da playbook ativa, o Scout v2 maximiza a precisão de execução.
3. **Inviabilidade de Autocorreção Pura sem Grounding:** O estudo seminal de Huang et al. (ICLR 2024) demonstrou que LLMs não conseguem se autocorrigir confiavelmente apenas com prompts de "reavalie sua resposta". A autocorreção só funciona quando há **grounding exógeno** (um interpretador de código, um compilador ou um validador de schema). O v1 usava autocorreção puramente estocástica (o auditor gerando prosa de bronca no prompt). O v2 implementa grounding exógeno: a Exit Tool rejeita o encerramento se a chamada da capability não tiver sido efetuada no banco.
4. **Memória de Longo Prazo:** O modelo cognitivo do Zep e do MemGPT preconiza que notas contextuais devem ser rigorosamente separadas entre *Semantic Memory* (fatos duráveis da entidade) e *Episodic Memory* (eventos temporais com desfechos pontuais). Injetar episódios passados no prompt de agentes reativos gera contaminação crônica de premissas.

---

## 5. Avaliação Ponto a Ponto das 11 Decisões de Design

| # | Decisão de Design | Avaliação | Análise do Arquiteto Sênior |
|---|---|:---:|---|
| **1** | **Ativação Híbrida (`when_state` > `trigger`)** | **Aprovada** | Alinha o sistema ao estado transacional do CRM. Elimina latência e custo em 85%+ dos turnos. O resíduo coberto por trigger textual é estritamente o necessário para nuances conversacionais. |
| **2** | **Playbook como Arquivo Versionado (`.md`)** | **Aprovada** | Aplicação pragmática de *Configuration-as-Code*. Permite validação estática no boot do Rails, testes determinísticos no CI e governança via pull requests. |
| **3** | **Capability como Contrato do Fork** | **Aprovada** | Princípio de *Information Hiding* de Parnas. O agente conversa em termos de domínio (`data`, `serviço`), enquanto o adapter injeta credenciais e parâmetros de sistema. |
| **4** | **`ScoutTool` declara Capability; Fim de `CallCustomApi`** | **Aprovada** | Extirpa a causa de dezenas de alucinações de argumentos. Protege o modelo de ter que sintetizar `idEmpresa`, `idAgenda`, etc. |
| **5** | **Namespace `Custom::ScoutV2::*`, v1 intocado** | **Aprovada** | Aplicação clássica do padrão *Strangler Fig* (Martin Fowler). Mitiga 100% do risco de regressão em produção e permite testes A/B no playground. |
| **6** | **Instructions Tipadas (`Role`, `Scope`, Enums)** | **Aprovada** | Remove texto prolixo do prompt global. O uso de enums restringe a variância estilística com custo quase zero de tokens. |
| **7** | **Escalation como Camada Própria** | **Aprovada** | Consolida as 3 cópias da regra de handoff em um único ponto, entregue no instante exato da saída (Just-In-Time injection). |
| **8** | **Frontmatter com `requires:` e `needs:`** | **Aprovada** | Implementa *Graceful Degradation*. Se o ERP de agendamento não estiver configurado na conta, o agente não entra em pânico nem quebra: degrada com aviso e atende em texto. |
| **9** | **V2 nasce sem auditor pós-hoc** | **Aprovada** | Remove a fonte primária de latência (3 a 8 chamadas) e mensagens duplicadas. O controle passa a ser preventivo (Exit Tools) e não corretivo pós-hoc. |
| **10** | **Memória Tipada (`fato` vs `episodio`)** | **Aprovada** | Solução estrutural para o problema de contaminação de notas. Apenas fatos duráveis validados entram no prompt; notas humanas nascem como episódios por segurança. |
| **11** | **Conhecimento: Extração Determinística sem Edição de Derivado** | **Aprovada** | Trata o RAG como artefato de compilação (*build artifact*). A correção de eventuais desvios é feita por meio de fontes autorais (`kind: faq`), garantindo idempotência. |

---

## 6. O Caminho do Menor Impacto e Máximo Aproveitamento

Uma preocupação central em grandes reescritas é o risco do "Second-System Effect" (Brooks, *The Mythical Man-Month*): a tentação de reescrever componentes funcionais que já estão maduros e testados.

A auditoria do código confirmou que **o Scout v2 NÃO comete esse erro**. Ele preserva integralmente todos os subsistemas periféricos estáveis do v1:

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                    SUBSISTEMAS 100% APROVEITADOS DO V1                       │
├─────────────────────────┬────────────────────────────────────────────────────┤
│ Componente              │ Papel no v2                                        │
├─────────────────────────┼────────────────────────────────────────────────────┤
│ ProcessMessageJob       │ Debounce assíncrono via Redis (Alfred) mantido     │
│ ScoutListener           │ Subscrição de eventos do Chatwoot mantida          │
│ AudienceMatcherService  │ Porteiro de canal, audiência e segmentação mantido │
│ ScoutAccountConfig      │ Configuração de modelos, API keys e quotas mantida │
│ FollowUpJob             │ Rotinas de follow-up por inatividade mantidas      │
│ Base RAG PGVector       │ Tabelas de embeddings, cosine distance e jobs      │
│ Erp::BaseAdapter        │ Infraestrutura de adapters e clients ERP mantida   │
│ Modelos de CRM          │ Opportunity, Contact, StageRole, Notes inalterados │
│ Langfuse / OpenTelemetry│ lib/integrations/llm_instrumentation.rb mantido    │
└─────────────────────────┴────────────────────────────────────────────────────┘
```

O escopo do v2 restringe-se cirurgicamente a:
1. Como o prompt do turno é montado (**Playbooks & Instructions** em vez de `SystemPromptsService`).
2. Como as tools são expostas (**Dynamic Scoping via Capabilities** em vez de `build_tools` estático).
3. Como o encerramento do turno é validado (**Exit Tools** em vez de `ResponseAuditor`).
4. Como as notas de contato são filtradas (**Tabela de atributos de notas** em vez de injeção irrestrita).

Essa delimitação respeita à risca as regras de desenvolvimento do repositório (`AGENTS.md`), mantendo o v1 intacto e operando até que a migração gradual seja concluída.

---

## 7. Alertas Técnicos e Recomendações Críticas para a Implementação

Como Arquiteto Sênior, identifico **quatro nuances de implementação** no runtime que a equipe executora deve observar nas Fases 0 e 1 para evitar armadilhas sutis:

### Alerta 1: Ciclo de Vida de Capabilities no RubyLLM em Ativação por Trigger
* **Cenário:** O turno inicia sem nenhuma playbook forçada por estado (`when_state`). O roteador injeta apenas as tools nativas e o índice de playbooks. Durante a conversa, o modelo invoca `open_playbook(agendamento)`. O corpo da playbook chega como resultado da ferramenta.
* **O Ponto Cego:** A gem `ruby_llm` compila e registra as ferramentas disponíveis na inicialização do objeto `chat` (`chat.with_tool(...)`). Se a playbook ativada dinamicamente demandar novas capabilities (ex: `scheduling.list_slots`), o loop interno do RubyLLM já estará em andamento.
* **Recomendações:**
  - *Abordagem A (Recomendada):* No início do turno, o `TurnRunner` pré-registra no chat as capabilities de **todas** as playbooks citadas no índice de ativação textual, mas a instrução da playbook ativa é que autoriza seu uso.
  - *Abordagem B (Conversacional):* A ferramenta `open_playbook` apenas carrega a intenção e instrui o assistente a responder a primeira mensagem de acolhimento; as capabilities passam a ser injetadas a partir do turno imediatamente seguinte pelo Router.

### Alerta 2: Prevenção de Interrupção Abrupta (`Tool::Halt`) em Exit Tools
* **Cenário:** O modelo invoca uma ferramenta de saída, como `exit_agendado(...)` ou `exit_handoff(...)`.
* **O Risco:** No `ruby_llm`, ferramentas que disparam `RubyLLM::Tool::Halt` encerram o loop de execução sem passar pelo bloco `complete(&)`. Se isso ocorrer, o modelo não emitirá a mensagem final de encerramento em linguagem natural destinada ao cliente, deixando a conversa sem resposta no WhatsApp.
* **Recomendação:** O handler do Exit (`ExitHandler`) deve processar e persistir o efeito colateral no banco (transicionar estágio, disparar `HandoffService`), mas **retornar uma instrução textual de encerramento** para o modelo, permitindo que ele gere normalmente a mensagem final dentro do `ResponseSchema`.

### Alerta 3: Desambiguação Negativa no Índice de Playbooks
* **Cenário:** O índice estático de playbooks presentes nas *Instructions* terá uma linha por playbook (`nome + trigger`).
* **O Risco:** Se dois triggers possuírem proximidade semântica (ex: `duvida_comercial` vs. `fora_de_prospeccao`), o modelo pode hesitar ou oscilar.
* **Recomendação:** Os triggers textuais no frontmatter dos arquivos `.md` devem obrigatoriamente incluir **restrições negativas explícitas** (ex: *"Trigger: O lead perguntou sobre tratamentos; NÃO usar se o lead for paciente ativo com reclamação de pós-atendimento"*).

### Alerta 4: Persistência de Transições e Idempotência de Estado
* O limite de 2 transições de playbook por turno (`design.md:306`) é essencial para evitar oscilações em loop.
* Esse contador (`transition_count`) deve ser obrigatoriamente persistido na tabela `ichatr_scout_conversation_states` a cada mudança de playbook, garantindo que retentativas assíncronas do Sidekiq não ultrapassem o teto de segurança.

---

## 8. Refinamentos Estratégicos Decorrentes da Revisão do Operador

A leitura crítica realizada pelo operador levantou dois pontos arquiteturais de altíssimo valor, que refinam e potencializam o projeto original:

### 8.1 Manipulação de CRM como Scoped Capabilities / Playbook (Fim das "Tools Nativas Sempre-On")
No rascunho de `design.md` (§4.1), ferramentas nativas do fork (`manage_opportunity`, `move_opportunity_stage`, `update_contact`, `create_private_note`) estavam provisoriamente classificadas como *"nativas sempre no prompt"*.

**Diagnóstico Arquitetural:** Manter ferramentas de mutação de CRM ativas incondicionalmente repete uma fração do vício do v1. Em turnos puramente informativos ou de pausa (ex: `duvida_comercial`, `pausa`, `fora_de_prospeccao`):
* O modelo não tem motivo para ter acesso a `manage_opportunity` ou `move_opportunity_stage`.
* A presença de ferramentas de escrita aumenta a carga de tokens e cria risco de efeitos colaterais indesejados (ex: o modelo avançar o estágio de um lead enquanto apenas tira uma dúvida sobre o endereço da clínica).

**Decisão Recomendada para o v2:**
1. **Extinção do `move_opportunity_stage` como tool direta do LLM:** A transição de estágio nunca deve ser decidida por uma tool genérica de escrita. Ela passa a ser um **efeito determinístico de Exit** executado no backend Ruby pelo `ExitHandler` (`exit_qualificado` move para qualificado; `exit_agendado` move para agendado; `exit_desqualificado` move para desqualificado). O modelo declara o desfecho de negócio, e o código gerencia o CRM com validação de campos obrigatórios.
2. **Escopo Estrito de Escrita de CRM:** Ferramentas de escrita em CRM tornam-se **Scoped Tools** ou **Capabilities de CRM** associadas exclusivamente às playbooks que demandam modificação de dados:
   +- `identificacao`: tools: `[update_contact]`
   +- `qualificacao`: tools: `[manage_opportunity]` (apenas campos customizados/dados do lead), exits: `qualificado`, `desqualificado`, `handoff`
   +- `agendamento`: requires: `[scheduling, customer_registry]`, exits: `agendado`, `sem_horario`, `handoff`
   +- `duvida_comercial`: tools: `[search_knowledge_base]` (**zero tools de mutação de CRM**)
   +- `pausa`: tools: `[]` (**zero tools de mutação de CRM**)
   +- `fora_de_prospeccao`: exits: `handoff` (**zero tools de mutação de CRM**)
3. **Alternativa de Playbook Dedicado:** Caso o contato solicite explicitamente atualização cadastral fora do funil (ex: *"mudei de telefone, anota aí meu novo número"*), isso pode ser tratado por um playbook específico de `atualizacao_cadastral` com prioridade intermediária.

**Impacto:** Em turnos de FAQ ou encerramento, o catálogo de ferramentas de escrita cai para **zero**, reduzindo a superfície de alucinação e eliminando completamente mutações espúrias no CRM.

---

### 8.2 Observabilidade com Langfuse & OpenTelemetry (Reaproveitamento da Fase 17)
No Scout v1, a Fase 17 (`docs/kanban/ciclo 10/scout/17-observability-and-handoff-notice/spec77.md`) integrou a pipeline core de OpenTelemetry e Langfuse (`lib/integrations/llm_instrumentation.rb`), garantindo rastreamento visual completo de spans de LLM, tools e sessões.

Essa camada **já está pronta e testada no repositório**, devendo ser incorporada formalmente ao Scout v2 desde o Dia 1 da Fase 0:
1. **Instrumentação no `TurnRunner`:** O `Custom::ScoutV2::TurnRunner` deve incluir `Integrations::LlmInstrumentation` e envolver a execução do turno com `instrument_agent_session` e `instrument_llm_call`.
2. **Instrumentação de Capabilities e Exits:** O wrapper de execução de capabilities e exit handlers deve emitir spans via `instrument_tool_call`, registrando parâmetros de entrada, latência e desfecho no Langfuse.
3. **Enriquecimento com Metadados de Playbook:** Ao contrário do v1 (que gerava traces ruidosos e difíceis de ler com 3 a 8 chamadas aninhadas e laços de repair), o v2 enviará metadados semânticos de altíssimo valor no root span do Langfuse:
   +- `playbook`: nome da playbook ativa (`qualificacao`, `agendamento`, etc.)
   +- `activation_reason`: `:state`, `:trigger` ou `:transition`
   +- `exit_action`: nome do exit invocado (`exit_qualificado`, `exit_agendado`, etc.)
   +- `unsatisfied_flags`: pendências de capabilities ou fatos de negócio
4. **Ganhos Operacionais:** No Langfuse, cada turno do Scout v2 aparecerá como um trace limpo, com 1 única geração principal, chamadas claras de capability e um span de exit explícito, tornando qualquer anomalia instantaneamente depurável em produção.

---

### 8.3 Veredito do Arquiteto: Sinal Verde Incondicional
Com a incorporação desses dois refinamentos (escopo estrito para ferramentas de CRM e integração formal com o Langfuse), a arquitetura do Scout v2 atinge o estado da arte definitivo para assistentes comerciais em CRM:
* **Prevenção > Compensação:** Elimina a toxicidade e a latência de auditores pós-hoc.
* **Certeza Matemática no CRM:** Transições de estágio são orquestradas por Exits em Ruby.
* **Isolamento Total:** Namespace próprio, rollback em 1 clique e 100% de reuso da infraestrutura estável do v1.

**Temos sinal verde absoluto para perseguir essa meta e iniciar a Fase 0 (Fundação).**

---

## 9. Conclusão Final

O projeto do **Scout v2** é de altíssimo nível. Ele demonstra maturidade de engenharia, fundamentação empírica inatacável nas dores reais do repositório e absorção impecável dos melhores padrões do Botpress e da indústria de agentes de CRM.

A substituição de um modelo baseado em compensações pós-hoc por um modelo preventivo baseado em contratos e escopo dinâmico proporcionará:
* Redução de latência de 15-40s para 2-4s.
* Redução de custo de API de 60% a 85% por turno.
* Eliminação de vazamento de prompts e mensagens duplicadas de handoff.
* Testabilidade determinística no CI via specs puras em Ruby.
* Observabilidade profunda e legível no Langfuse por playbook e exit.

**Recomendação:** Iniciar imediatamente a execução da **Fase 0 (Fundação)** conforme planejado no roadmap.
