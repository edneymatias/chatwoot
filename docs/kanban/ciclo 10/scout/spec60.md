# Especificação Técnica: Scout — Motor de Agentes IA (Qualificação Comercial & Multiuso)

**Status**: Backlog / Especificação Consolidada — **revisada** contra o código real do fork  
**Data**: 2026-08-16 (revisão técnica em 2026-08-17)  
**Contexto**: Implementação nativa de um motor de Inteligência Artificial / Agente autônomo para o Chatwoot, batizado **Scout** ("o batedor que vai na frente qualificando os potenciais clientes"), com suporte a múltiplos cenários, focado primariamente na qualificação comercial integrada ao funil de Oportunidades (Kanban), suporte a Tool Calling nativo, preservação de atribuição de anúncios (Meta CTWA / Referral), chamadas de APIs REST / Webhooks para máxima flexibilidade e convivência elegante com atendentes humanos.

> **Nota de revisão**: este documento foi confrontado linha a linha com o código atual do fork. Pontos corrigidos ou reavaliados estão marcados com `> ⚠️ Revisão:`. A premissa de arquitetura que rege todas as correções é **minimizar a superfície de acoplamento com o upstream** — o fork não pode se desacoplar 100%, mas cada decisão de design deve reduzir os pontos de contato com `enterprise/` e evitar modificar arquivos core quando uma extensão em `custom/` resolve o mesmo problema.

---

## 1. Visão Geral e Propósito

O objetivo é criar uma alternativa nativa e robusta inspirada no conceito do Captain/Agentes do Chatwoot, porém:
1. **Focada no Funil Comercial**: Alinhamento direto com o módulo de Oportunidades (`Opportunity`, `PipelineStage` — não existe model `Pipeline` separado neste fork, o funil é modelado apenas pelas etapas posicionais de `PipelineStage`), capaz de realizar triagem de qualificação (dor, orçamento, autoridade, timing, interesse, origem de campanha) e avançar/desqualificar leads no Kanban.
2. **Preservação de Atribuição de Campanha & Anúncios (Meta CTWA / Referral)**: Garantia de que a origem do anúncio (criativo, thumbnail, headline, ID do anúncio) seja mantida intacta e vinculada à oportunidade no Kanban, mesmo após dezenas de mensagens trocadas com o bot.
3. **Não Limitada ao Comercial**: Arquitetura desacoplada e extensível para suportar múltiplos assistentes e cenários (suporte N1, triagem, agendamento de reuniões, onboarding).
4. **Orientada a Metas e Ferramentas (Goal-Driven + Tool Calling)**: Conversação fluida e natural, com capacidade de invocar ferramentas nativas em Ruby e APIs REST / Webhooks externas configuráveis de forma simples e rápida (com suporte futuro/opcional ao protocolo MCP).
5. **Interface Guiada ao Universo Comercial**: Telas de configuração direcionadas a produtos, serviços, tabelas de preços, base de conhecimento de vendas (site, landing pages, PDFs de propostas/catálogo) e tratamento de objeções.
6. **Human-in-the-Loop Elegante**: Transbordo suave com criação de Nota Privada estruturada (resumo da qualificação para o vendedor), pausa automática sob intervenção humana e controle manual por conversa.
7. **Mecanismos do Mundo Real**: Debounce no Redis (buffer de mensagens), suporte multimodal all-in-one (áudio e imagens com 1 única chave), respeito aos horários de atendimento e Fail-Safe imediato se o saldo/chave expirar.

---

## 2. Preservação de Atribuição Meta/WhatsApp (CTWA, Criativos e Campanhas)

> ⚠️ **Revisão**: esta seção descreve um pipeline que **já está implementado e em produção** neste fork — `Custom::ReferralAttributionService` (`custom/app/services/custom/referral_attribution_service.rb`) e `Custom::AutomationRules::ActionService#find_referral_message` / `#create_opportunity` (`custom/app/services/custom/automation_rules/action_service.rb:10-42`) já extraem plataforma, `campaign_source_id`, `ad_id`, headline, body e thumbnail do referral, distinguem tráfego orgânico de pago (`organic_referral?`) e persistem tudo na `Opportunity`, com idempotência por `origin_conversation_id`. **O Scout não deve reimplementar esta lógica.** A ferramenta nativa `manage_opportunity` (seção 10) deve chamar esses serviços existentes, não recriar a query SQL abaixo.

Quando um lead entra via anúncio de WhatsApp (Click to WhatsApp - CTWA) ou post orgânico do Instagram/Facebook, a primeira mensagem recebida carrega o payload `referral` nos `content_attributes`.

```
Lead clica no Anúncio ──► Msg 1 com Referral (Criativo/Headline) ──► Bot assume a conversa
                                                                            │
                                    ┌───────────────────────────────────────┴──────────────────┐
                                    ▼                                                          ▼
                      (Triagem em 5-10 turnos)                                     (Oportunidade Criada/Movida)
                      Referral permanece imutável                                  Herda Criativo, Thumbnail
                      no histórico de mensagens                                    e Campanha da Msg 1
```

### 2.1. Requisitos de Atribuição Multi-Etapas:
1. **Persistência Imutável do Referral**:
   - Mensagens `incoming` preservam `content_attributes['referral']` no PostgreSQL indefinidamente.
   - O bot e as notas privadas apenas geram mensagens `outgoing` e `:activity`, garantindo que os metadados do lead nunca sejam corrompidos.
2. **Query Segura de Extração de Origem**:
   - Ao criar ou atualizar a `Opportunity` vinculada à conversa (`origin_conversation_id`), o serviço busca a mensagem original exata contendo o referral:
     ```ruby
     conversation.messages.incoming
                 .where("(content_attributes #>> '{}')::jsonb -> 'referral' IS NOT NULL")
                 .order(created_at: :asc)
                 .first || conversation.messages.incoming.order(created_at: :asc).first
     ```
   - O card da Oportunidade no Kanban exibe thumbnail do criativo, nome da campanha, headline e anúncio que gerou o lead.
3. **Herança Limpa de Responsável (Assignee)**:
   - Durante a triagem, a oportunidade permanece vinculada ao time comercial sem herdar o ID do bot como usuário comercial.
   - Ao executar o transbordo (`handoff`), o responsável é atribuído ao SDR/Vendedor humano definitivo.
4. **Disparo de Conversão Meta CAPI (Opcional)**:
   - Ao qualificar o lead com sucesso, o sistema pode enviar o evento de conversão Meta CAPI (ex: `LeadQualificado` ou `Contact`) usando o `ctwa_clid` da mensagem inicial.

---

## 3. Parecer de Licenciamento & Diretrizes de Conformidade (O que NÃO fazer)

### 3.1. Base Legal
- **Licença do Chatwoot Core (MIT Expat)**: Todo o código do Chatwoot fora da pasta `enterprise/` é licenciado sob a licença **MIT** (veja [`LICENSE`](file:///home/matias/dev/chatwoot/LICENSE)). A licença MIT garante total liberdade para modificar, criar novos recursos, comercializar e distribuir sem restrições.
- **Isolamento em `custom/`**: Todo o motor de IA e as ferramentas comerciais residem no diretório `custom/`, consumindo apenas interfaces e models abertos.

> ⚠️ **Revisão — Minimização de acoplamento com upstream**: além de não copiar código de `enterprise/`, o Scout deve minimizar a superfície de contato com o core sempre que uma alternativa em `custom/` resolver o mesmo problema, mesmo sabendo que o desacoplamento total não é possível:
> - **Não adicionar colunas em tabelas core** (`inboxes`, `conversations`, `accounts`) para necessidades do Scout — usar tabelas próprias (`ichatr_scouts`, `ichatr_scout_inboxes`) com FKs para as tabelas core, como já é o padrão de `Opportunity`/`PipelineStage`.
> - **Consumir apenas interfaces públicas e estáveis do core**, como `conversation.bot_handoff!` (`app/models/conversation.rb:175-180`, método genérico e não específico do Captain) e o dispatcher de eventos — nunca herdar de/depender de classes de `enterprise/` (`HookExecutionService`, `Llm::BaseAiService`, `Captain::Tools::*`), que são referência de leitura, não base de código.
> - **Preferir dependências já vendorizadas e públicas** (ex: gem `ruby_llm`, ver seção 6) a reimplementar integrações que o core/Gemfile já resolve.
> - Isso reduz o risco de quebra em cada sync com o upstream (`git merge --no-ff <tag>`) e mantém o Scout auditável/removível de forma isolada.

### 3.2. 🚫 Diretrizes Estritas: O que NÃO Fazer
1. **NÃO copiar código da pasta `enterprise/`**: Todo o motor de IA é escrito do zero de forma limpa na pasta `custom/`.
2. **NÃO tentar burlar verificações de licença da pasta `enterprise/`**: Não criar patches para burlar limites do Enterprise oficial da Chatwoot Cloud.
3. **NÃO remover avisos de Copyright**: Manter o cabeçalho original da Chatwoot Inc. nos arquivos base MIT.
4. **NÃO depender de servidores da Chatwoot Cloud**: Conexão direta e autônoma com os provedores de LLM via chaves próprias.

---

## 4. Gestão de Saldo, Ciclo de Status e Transbordo de Emergência (Fail-Safe)

### 4.1. Como o Capitão Oficial Trata Créditos (Mapeamento Upstream)
Conforme mapeado no código oficial do Chatwoot (`HookExecutionService`, `Inbox`, `PlanUsageAndLimits`):
- **Unidade de Medida**: Controlado por `captain_responses` (respostas geradas pelo bot) e `captain_documents` (limite de itens no RAG).
- **Validação em Tempo Real**: O Chatwoot verifica `inbox.captain_active?` (`account.usage_limits[:captain][:responses][:current_available].positive?`).
- **Ao esgotar o saldo (`current_available <= 0`)**: O Chatwoot dispara `perform_handoff` (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:56-68`):
  1. Envia mensagem ao cliente: *"Transferring to another agent for further assistance."*
  2. Executa `conversation.bot_handoff!`, abrindo a conversa na fila humana.
  3. Se fora do expediente, envia mensagem de ausência (`OutOfOffice`).

> ⚠️ **Revisão**: `bot_handoff!` (`app/models/conversation.rb:175-180`) é um método **genérico do core**, sem guarda de status `pending` embutida — ele apenas seta `waiting_since` se vazio, limpa `assignee_agent_bot`, chama `open!` e dispara o evento `CONVERSATION_BOT_HANDOFF`. A checagem de `conversation.pending?` acontece em `perform_handoff` (código Enterprise), antes de chamar o método. O Scout deve replicar essa checagem no seu próprio fluxo (seção 4.2), não assumir que `bot_handoff!` a faz.

### 4.2. Nossa Abordagem de Fail-Safe Handoff (Ichatr Bot)
Garantimos que **nenhuma conversa jamais fique presa em `pending` ou seja perdida**:
1. **Detecção Imediata**: Se o saldo de respostas zerar ou a chave de API (BYOK) falhar (ex: erro 429 de cota/chave inválida).
2. **Abertura Imediata na Fila Humana**: Dispara `conversation.bot_handoff!`, alterando o status para **`open`** e acionando o alerta para os atendentes humanos.
3. **Nota Privada de Alerta (Amarela)**: Cria uma nota interna na conversa avisando a equipe comercial:
   > `⚠️ [IA Pausada]: A conversa foi transferida para atendimento humano devido a esgotamento de saldo/limite de API.`
4. **Preservação de Dados no Funil**: A Oportunidade criada na etapa de *Triagem* permanece salva no Kanban com todos os dados coletados até o momento.

---

## 5. Cruzamento com Upstream do Chatwoot & Soluções do Mundo Real

```
┌───────────────────────────────┬───────────────────────────────────┬───────────────────────────────────┐
│ Recurso do Mundo Real        │ O que o Chatwoot Upstream tem     │ Como nosso Motor se Conecta       │
├───────────────────────────────┼───────────────────────────────────┼───────────────────────────────────┤
│ 🛑 Debounce do WhatsApp       │ Sidekiq + Redis                   │ Enfileira Job com delay de 5s;    │
│    (Buffer de mensagens)      │                                   │ agrupa mensagens recebidas em lote│
│                               │                                   │ antes de chamar o LLM.            │
├───────────────────────────────┼───────────────────────────────────┼───────────────────────────────────┤
│ 🎙️ Áudios e Imagens           │ `Message#attachments`             │ Identifica `file_type: :audio` e  │
│    (Multimodalidade)          │ (`Attachment` + `ActiveStorage`)  │ `:image` e despacha para o gateway│
│                               │                                   │ multimodal com 1 única chave.     │
├───────────────────────────────┼───────────────────────────────────┼───────────────────────────────────┤
│ ⏰ Horário Comercial          │ Concern `OutOfOffisable`          │ Consulta `inbox.out_of_office?` e │
│    (Business Hours)           │ (`Inbox#working_hours_enabled?`)  │ instrui o prompt automaticamente. │
├───────────────────────────────┼───────────────────────────────────┼───────────────────────────────────┤
│ 🪃 Follow-up com Nudges &     │ Sidekiq (infra genérica de jobs   │ `Custom::Scout::FollowUpJob`      │
│    Handoff de Resgate         │ agendados, sem job pronto p/ isso)│ (Fase 22): cadência escalonada    │
│    (Contato em silêncio)      │                                   │ (`follow_up_delays_hours`, até 2  │
│                               │                                   │ nudges) e, se ainda em silêncio,  │
│                               │                                   │ move a Oportunidade pro estágio de│
│                               │                                   │ resgate (`rescue_stage_id`) e faz │
│                               │                                   │ handoff — nunca marca como Perdido│
│                               │                                   │ por conta própria.                │
├───────────────────────────────┼───────────────────────────────────┼───────────────────────────────────┤
│ 🛡️ Fail-Safe sem Saldo        │ `conversation.bot_handoff!`       │ Força status para `open` e cria   │
│                               │                                   │ Nota Privada amarela de alerta.   │
├───────────────────────────────┼───────────────────────────────────┼───────────────────────────────────┤
│ 🧪 Playground de Teste        │ Padrão Vue 3 em `components-next` │ Endpoint `/playground` para simu- │
│                               │                                   │ lar e visualizar chamadas de tools│
└───────────────────────────────┴───────────────────────────────────┴───────────────────────────────────┘
```

---

## 6. Estratégia de Chaves & Modelo de Consumo (BYOK vs. Sistema)

> ⚠️ **Revisão — Gateway LLM**: o `Gemfile` já declara `gem 'ruby_llm', '>= 1.14.1'` (resolvido em `1.15.0`, `Gemfile.lock:855`) e `ruby_llm-schema`, uma gem **pública/MIT multi-provider** (OpenAI, Anthropic, Gemini, Ollama, OpenRouter) com tool-calling nativo e suporte a anexos multimodais já unificado. **Isso elimina a necessidade de construir um "LLM Gateway All-in-One" do zero** (como planejado originalmente na Fase 1 do roadmap, seção 11) — o Scout deve consumir `ruby_llm` diretamente para chamadas de provedor, e reservar código próprio apenas para orquestração (Context Builder, Tool Executor, debounce, fail-safe), que é onde está o valor real deste motor. Isso também reduz a superfície de acoplamento com o upstream: menos código próprio para manter, mais uma dependência pública já auditada pelo ecossistema Rails.

Para evitar que o cliente final precise contratar múltiplos serviços separados (transcrição, visão, texto):

1. **Provedores All-in-One com 1 Única Chave**:
   - **Google Gemini (2.0 Flash / Pro)**: Processa texto, visão e áudio nativamente com custo baixíssimo.
   - **OpenAI (GPT-4o + Whisper)**: 1 chave resolve texto, imagens e áudio.
   - **OpenRouter**: Acesso a múltiplos modelos com 1 única conta.
2. **Modelo de Consumo**:
   - **Modo Padrão (BYOK - Bring Your Own Key)**: O cliente insere a chave na tela de configurações da conta. Sem custo ou risco para o operador.
   - **Modo Sistema (Managed / Opcional)**: Chave global no `.env` com contadores de telemetria (`tokens_consumed`, `messages_processed`) no Postgres.

---

## 7. Interface (UI) Especializada para o Universo Comercial

A interface do Assistente na Dashboard (Vue 3 + Tailwind) é projetada especificamente com os seguintes módulos:

### 7.1. Aba de Produtos, Serviços & Ofertas
- **Catálogo de Produtos/Planos**: Cadastro de itens comercializados, faixas de preços, planos recorrentes e regras de parcelamento.
- **Proposta de Valor e Diferenciais**: Resumo do "pitch" comercial para o bot usar nas argumentações de vendas.

### 7.2. Base de Conhecimento Comercial (RAG de Vendas)
- **Links de Sites & Landing Pages**: Crawling de URLs de páginas de vendas, cases de sucesso e páginas de produto.
- **Documentos & Catálogos (PDFs/Docs)**: Upload de manuais comerciais, catálogos técnicos, tabelas de preços e políticas de garantia.
- **FAQ Comercial & Tratamento de Objeções**: Perguntas e respostas focadas em objeções comuns (*"por que é mais caro que o concorrente X?"*, *"qual o prazo de entrega/implantação?"*).

### 7.3. Configuração do Funil & Critérios de Qualificação
- **Etapas Vinculadas**: Seleção da Etapa de Triagem inicial, Etapa de Qualificado e Etapa de Descarte (não há seleção de "Pipeline" separado — este fork modela o funil apenas via `PipelineStage`).
- **Campos de Qualificação Obrigatórios**: Seleção dos atributos a extrair (ex: Dor principal, Orçamento estimado, Prazo de decisão, Decisor final).
- **Regras de Descarte / Sucesso**: Para qual etapa mover quando qualificado vs. qual etapa mover quando sem fit (com motivo de perda).

---

## 8. Diagrama de Arquitetura

```mermaid
flowchart TD
    subgraph Chatwoot_Core["Chatwoot Core / Events"]
        Msg[Incoming Message com Referral] --> Event[Event Dispatcher / Hook]
        Event --> RedisDebounce[Redis Debounce Buffer: 5s]
        RedisDebounce --> Job[Scout::ProcessMessageJob]
    end

    subgraph Scout_Engine["Scout Engine (Rails custom/)"]
        Job --> AgentRunner[Scout::AgentRunner]
        AgentRunner --> BalanceCheck{Cota/Saldo OK / Chave Válida?}
        BalanceCheck -- NÃO --> FailSafe[Fail-Safe: Status OPEN + Nota de Alerta]
        BalanceCheck -- SIM --> Attachments[Verifica Attachments: Áudio / Imagem]
        Attachments --> HoursCheck[Verifica Inbox.out_of_office?]
        HoursCheck --> ContextBuilder[Context Builder: Persona + Produtos + RAG]
        ContextBuilder --> LLMClient[ruby_llm: Gemini / OpenAI / Claude / Ollama]
        LLMClient --> ToolExec[Scout::ToolExecutor]
    end

    subgraph Tool_System["Tool System: Nativas + REST APIs"]
        ToolExec --> NativeTools[Ferramentas Nativas Ruby]
        ToolExec --> RestTools[APIs REST / Webhooks Customizados]
    end

    subgraph Commercial_Funnel["Módulo de Oportunidades (Kanban)"]
        NativeTools --> OppCreate[Criar Oportunidade em Triagem com Referral de Origem]
        NativeTools --> OppQualify[Atualizar Atributos: Dor, Orçamento, Origem]
        NativeTools --> OppStage[Mover Etapa: Qualificado / Desqualificado]
        NativeTools --> Handover[Gerar Nota Privada + Transbordo Humano]
    end
```

---

## 9. Modelagem de Dados Proposta

> ⚠️ **Revisão**: namespace `Ai::` trocado por classes flat (`Scout`, `ScoutInbox`, `ScoutTool`), alinhado à branding do produto e à convenção já usada por `Opportunity`/`PipelineStage` (sem módulo aninhado). `pipeline_id` removido — **não existe model `Pipeline`** neste fork; o funil é modelado apenas por `PipelineStage` (posicional, sem conceito de "funil" separado) e `Opportunity.status` (`open/won/lost`). Campos de cota/crédito adicionados (ver seção 4.3, nova). Migrations seguem o padrão do fork: timestamp `21260...`, tabelas prefixadas `ichatr_`.

### 9.1. `Scout` (`ichatr_scouts`)
- `account_id` (integer, indexed)
- `name` (string): Ex: "SDR Qualificador Comercial"
- `description` (text)
- `system_prompt` (text): Instruções da persona, regras de qualificação.
- `provider` (string): `gemini`, `openai`, `anthropic`, `openrouter`, `ollama`
- `model_name` (string): `gemini-2.0-flash`, `gpt-4o-mini`, `claude-3-5-sonnet`, etc.
- `api_key_override` (string, **`encrypts`, obrigatório** — ver seção 4.3): Suporte a BYOK por assistente/conta.
- `temperature` (float, default: 0.2)
- `default_pipeline_stage_id` (bigint, optional): Etapa inicial de triagem.
- `qualified_stage_id` (bigint, optional): Etapa para onde mover lead qualificado.
- `unqualified_stage_id` (bigint, optional): Etapa de descarte (Perdido).
- `rescue_stage_id` (bigint, optional, Fase 22): Etapa de resgate — para onde a Oportunidade é
  movida quando o contato não responde a nenhum follow-up e a conversa é liberada para um humano.
  Nunca é o mesmo que marcar a Oportunidade como `lost`; é um estágio de funil normal, revisável por
  um humano.
- `product_catalog` (jsonb): Catálogo de produtos, preços e ofertas.
- `knowledge_sources` (jsonb): URLs rastreadas, documentos e FAQs comerciais.
- `enabled_tools` (jsonb): Lista de ferramentas nativas e APIs ativas.
- `handover_team_id` (bigint, optional): Time padrão para transbordo.
- `debounce_delay_seconds` (integer, default: 5): Janela de buffer de mensagens.
- `follow_up_delays_hours` (jsonb array of integer, default: `[2, 12, 24]`, Fase 22): cadência
  escalonada de silêncio (em horas desde a última mensagem visível) para cada etapa — nudge 1, nudge
  2, handoff de resgate. Substitui o campo único `follow_up_delay_hours` planejado originalmente
  aqui (nunca implementado) — um único intervalo de 24h era longo demais para o primeiro sinal de
  vida num atendimento comercial via WhatsApp.
- `auto_pause_on_human_message` (boolean, default: true)
- `active` (boolean, default: true)
- `responses_quota` (integer, default: `-1`): Cota de respostas geradas. `-1` = ilimitado (override para testes/planos sem billing). Ver seção 4.3.
- `responses_consumed` (integer, default: `0`): Contador incremental de respostas geradas pelo Scout.
- `feature_memory` (boolean, default: `true`): Espelha `assistant.config['feature_memory']` do
  Captain (`enterprise/app/listeners/captain_listener.rb`) — quando ativo, gera notas de contato ao
  final de uma qualificação/handoff, reaproveitando o mesmo mecanismo de memória do Captain
  (`Captain::Llm::ContactNotesService` → `contact.notes` → `LlmFormatter::ContactLlmFormatter`).
  Ver Fase 02.

### 9.2. `ScoutInbox` (`ichatr_scout_inboxes`)
- Tabela pivô associando `scout_id` com `inbox_id`. Evita adicionar coluna em `inboxes` (core) — ver princípio de minimização de acoplamento, seção 3.2.

### 9.3. `ScoutTool` (`ichatr_scout_tools`)
- `account_id` (integer)
- `name` (string): Ex: "Consultar Estoque / ERP"
- `description` (text): Descrição para o LLM saber quando chamar a ferramenta.
- `endpoint_url` (string): URL da API REST.
- `http_method` (string, default: `'POST'`): `GET`, `POST`, `PUT`.
- `auth_headers` (jsonb, **`encrypts`, obrigatório** — ver seção 4.3): Headers HTTP de autenticação.
- `parameters_schema` (jsonb): Schema JSON dos parâmetros extraídos pelo LLM.
- `enabled` (boolean, default: true)
- `response_template` (text, opcional, Liquid — Fase 13): quando preenchido, molda o corpo da resposta antes de chegar à LLM (`{{ r.campo }}`); vazio preserva o comportamento atual (JSON parseado ou corpo cru).

### 9.4. Migration adicional em `Opportunity` (core do Kanban, tabela custom já existente)
- `lost_reason` (string, optional): necessário para a ferramenta nativa `move_opportunity_stage` (seção 10) registrar o motivo de descarte. Não existe hoje em `custom/app/models/opportunity.rb` — nova migration `ichatr_` sob `custom/`, sem tocar em tabelas core.

## 4.3. Cota de Respostas (Groundwork para Billing Futuro)

> Estrutura rudimentar e deliberadamente simples — **sem validação de assinatura/cobrança nesta fase**. O objetivo é ter o campo de dados e o ponto de checagem prontos para quando uma fase de billing for introduzida, sem bloquear o lançamento do Scout.

- `Scout#quota_available?` — `responses_quota == -1 || responses_consumed < responses_quota`.
- Checado no `BalanceCheck` do fluxo Fail-Safe (seção 4.2, diagrama seção 8) junto com a validação de chave de API.
- `responses_consumed` incrementado a cada resposta gerada pelo `Scout::AgentRunner` (uma unidade por turno de resposta do LLM, análogo a `captain_responses` do Captain oficial — ver seção 4.1).
- `-1` é o valor usado para desbloquear cota ilimitada em ambientes de teste/desenvolvimento e para contas sem controle de billing ativo.
- Fase futura de billing (fora de escopo aqui) consome os mesmos campos: validação de plano/assinatura passa a decidir o valor de `responses_quota`, sem mudança de schema.

---

## 10. Catálogo de Ferramentas Nativas

1. `manage_opportunity(action, title, stage_id, estimated_value, custom_attributes)`:
   - Cria ou atualiza os campos comerciais da oportunidade no funil, preservando o `origin_conversation_id` e os metadados de anúncio/referral.
2. `move_opportunity_stage(stage_id, lost_reason)`:
   - Move o card no Kanban e preenche motivo de descarte caso movido para perdido.
3. `update_contact(name, email, phone, custom_attributes)`:
   - Atualiza o perfil do contato.
4. `create_private_note(content)`:
   - Registra a nota interna amarela com a síntese de qualificação comercial para o vendedor.
5. `handover_to_human(assignee_id, team_id, reason)`:
   - Pausa a IA e transfere a conversa para o time ou atendente.
6. `call_custom_api(tool_id, payload)`:
   - Despacha chamada HTTP REST para qualquer serviço ou webhook externo configurado.

---

## 11. Roadmap de Implementação

> ⚠️ **Revisão**: fases reordenadas e escopo ajustado após a revisão técnica desta seção. A Fase 1 não inclui mais um "LLM Gateway All-in-One" (a gem `ruby_llm` já resolve isso — seção 6), e uma nova Fase 3 de Hardening de Produção foi inserida antes de qualquer fase que grave campos criptografados (`api_key_override`, `auth_headers`) em produção, por depender do item de backlog [`11-production-secrets-encryption-hardening`](../11-production-secrets-encryption-hardening/spec61.md) (chaves de `ActiveRecord::Encryption` ausentes no Swarm de produção).

- [ ] **[Fase 1 — Core & Modelo de Dados](01-core-and-data-model/spec62.md)**: Migrations sob `custom/` (`Scout`, `ScoutInbox`, `ScoutTool`, `lost_reason` em `Opportunity`), integração com `ruby_llm` para chamadas multi-provider e tool-calling (Gemini, OpenAI, Claude, Ollama), campos de cota (`responses_quota`/`responses_consumed`, seção 4.3).
- [ ] **[Fase 2 — Ferramentas Nativas & Pipeline](02-native-tools-and-pipeline/spec63.md)**: Implementação das ferramentas Ruby para Oportunidades (`manage_opportunity`, `move_opportunity_stage`, `update_contact`, `create_private_note`, `handover_to_human`), reutilizando `Custom::ReferralAttributionService` para atribuição Meta/Referral (seção 2) e o Fail-Safe Handoff (seção 4.2/4.3).
- [ ] **[Fase 3 — Hardening de Produção](03-production-hardening/spec64.md)** *(bloqueante para dados sensíveis)*: Resolver `ActiveRecord::Encryption` em produção (Docker Swarm secrets ou `environment:`) antes de habilitar `api_key_override`/`auth_headers` em ambiente real — depende do backlog [`11-production-secrets-encryption-hardening`](../11-production-secrets-encryption-hardening/spec61.md).
- [ ] **[Fase 4 — Tool REST/Webhook Externa](04-external-rest-webhook-tool/spec65.md)**: Executor de Ferramentas Externas REST / Webhooks (`call_custom_api`, `ScoutTool`).
- [ ] **[Fase 5 — UI Comercial](05-commercial-ui/spec66.md)**: Interface Web (Vue 3 + Tailwind) para gestão de Scouts, catálogo de produtos/ofertas, RAG comercial, configuração do Funil e Playground de teste.
- [ ] **[Fase 6 — Configuração de LLM em Nível de Conta](06-account-llm-config/spec70.md)**: Substitui o BYOK por Scout (`Scout#provider`/`model_name`/`api_key_override`) por uma configuração única em nível de conta (`ScoutAccountConfig`), compartilhada por todos os Scouts — uma conta usa um único provedor (Gemini/OpenAI/Anthropic). Move a tela de configuração para fora do módulo Settings, para um submenu dedicado em Scout ("Configurações").
- [ ] **[Fase 7 — Busca Vetorial na Base de Conhecimento (RAG)](07-rag-knowledge-search/spec67.md)**: Refatora a injeção cega de conteúdo (`AgentRunner#build_knowledge_instructions`) por recuperação sob demanda via embeddings — reaproveita o pipeline de extração já existente (`ScoutKnowledgeSource`/`ProcessJob`, Fase 1), inspirado na solução do Captain (`pgvector`/`neighbor`, já presentes no `Gemfile` base). Lê provedor/modelo/chave da `ScoutAccountConfig` da Fase 6; contas com provedor Anthropic não têm a ferramenta de busca registrada (sem suporte a embeddings).
- [ ] **[Fase 8 — Arquitetura de Guardrails do System Prompt](08-system-prompt-guardrails/spec71.md)**: Camada fixa de guardrails do system prompt do Scout (escopo, anti-alucinação, anti-falsa-promessa, fallback de handoff, saída JSON estruturada), inspirada na arquitetura do Captain (`Captain::Llm::SystemPromptsService#assistant_response_generator`, `Captain::Llm::AssistantChatService`), aditiva às instruções configuráveis pelo operador em `Scout#system_prompt`. Estabelece o ponto único de interceptação da resposta final (`AgentRunner#process_response`) necessário para a Fase 12.
- [ ] **[Fase 9 — Inteligência de Funil: Estágios & Campos de Qualificação](09-required-qualification-attributes/spec74.md)**: Injeção dos estágios configurados do Funil (qualificado/desqualificado), dos campos obrigatórios por estágio (`PipelineStageRequiredField`) e dos campos globais de qualificação do Scout (`ScoutRequiredField`) no system prompt, com enforcement centralizado em `Custom::Scout::OpportunityStageTransitionService` (usado por `move_opportunity_stage` e `manage_opportunity`) e handoff automático ao atingir o estágio qualificado.
- [ ] **[Fase 10 — Handoff Automático em Intervenção Humana](10-in-conversation-ui/spec68.md)**:
  quando um humano responde publicamente numa conversa `pending` de uma inbox com Scout, a conversa
  é reaberta de forma síncrona (mesmo mecanismo do Captain,
  `Message#mark_pending_conversation_as_open_for_human_response`), evitando resposta colidente do
  Scout. Sem nenhum elemento visual — ver Fase 15.
  > ⚠️ **Revisão**: escopo reduzido em duas passadas de brainstorming. Primeira: o botão manual de
  > Pausar/Retomar e o campo `auto_pause_on_human_message` (seção 9.1, nunca implementado) foram
  > cortados, substituídos pelo mecanismo do Captain. Segunda: todo o escopo visual (badge de
  > status, link para o Kanban) foi movido para a Fase 15, para destravar o teste do MVP sem
  > bloquear em decisões de UI. Ver nota de revisão em `10-in-conversation-ui/spec68.md`.
- [ ] **[Fase 11 — Telemetria & E2E](11-follow-up-telemetry-e2e/spec69.md)** *(escopo reduzido — o job de follow-up saiu daqui, ver Fase 22)*: telemetria de tokens/cota e testes ponta a ponta. O `Scout::FollowUpJob` originalmente previsto nesta fase (seção 5) foi generalizado e especificado como Fase 22, após decisão de brainstorming dedicada.
- [ ] **[Fase 12 — Auditor de Resposta](12-response-auditor/spec78.md)** *(saiu do preview — evidência direta de produção, ver spec)*: Dois auditores de LLM independentes que rodam depois da resposta final ser gerada e antes de ser entregue (`AgentRunner#process_response`, ponto único de interceptação da Fase 8) — um classificador de ação (continue/handoff, independente do texto da resposta) e um detector de consistência (resposta vs. tool calls reais do turno, cobrindo tanto promessa futura quanto afirmação retroativa de ação não executada), inspirados em `Captain::Conversation::V1ActionClassifier`/`V1FalsePromiseHandler` mas adaptados (grounding em tool calls reais, modelo único por conta). Preview original em `12-response-auditor/spec-preview.md`.
- [ ] **[Fase 13 — Teste de Requisição & Formato de Saída das Ferramentas Externas](13-tool-testing-and-response-shaping/spec73.md)**: Botão de teste de requisição (com payload de exemplo) na configuração de `ScoutTool`, suporte a path params (`{{param}}` na URL, Liquid estrito) e querystring automática para `GET` (corrige descarte silencioso do payload em GET), e `response_template` (Liquid) para moldar o corpo da resposta antes de chegar à LLM — inspirado em `Captain::CustomTool`/`Toolable`. Depende da Fase 4.
- [ ] **[Fase 14 — Detecção de Continuidade de Oportunidade](14-opportunity-continuity-detection/spec75.md)** *(problema registrado durante a Fase 10; especificação completa após brainstorming dedicado — sem precedente no Captain, que não tem noção de Oportunidade/Kanban)*: busca de Oportunidades abertas escopada por contato (`contact_id` + `status: open`), exposta como contexto estruturado no system prompt ao lado da memória de contato já existente (`contact.notes`); `manage_opportunity` passa a exigir declaração explícita de `opportunity_id` quando há candidatos, validada deterministicamente no backend; sem declaração válida, não decide sozinho — registra nota privada e deixa para revisão humana. Preview original (problema + exemplos) em `14-opportunity-continuity-detection/spec-preview.md`. **Implementada**; ajuste pontual aplicado depois (`manage_opportunity#update_opportunity` agora chama `opp.attach_conversation!(conversation)` no caso `:reuse`, para que a conversa de continuidade fique corretamente vinculada via `OpportunityConversation`).
- [ ] **[Fase 15 — Indicadores Visuais do Scout (preview)](15-scout-visibility-indicators/spec-preview.md)** *(escopo visual da Fase 10 movido pra cá, sem especificação completa ainda)*: badge de status na conversa, indicador/link para a Oportunidade associada (reavaliando a seção "Oportunidades" já existente no painel de contato — recolhida por padrão, sem navegação direta pro Kanban), e uma ideia nova ainda não desenvolvida — indicador comparando resultado do Scout com desempenho de SDRs humanos.
- [ ] **[Fase 16 — Ativação do Scout em Qualquer Canal](16-cross-channel-activation/spec76.md)** *(bug encontrado ao testar o MVP ponta a ponta — WhatsApp nunca foi requisito de restrição de canal)*: remove o gate de `channel_type == 'Channel::Whatsapp'` em `Custom::ScoutListener`; novo `Custom::Inbox#active_bot?` (`super || scout_active?`, mesmo padrão de `Enterprise::Inbox#active_bot?`/Captain) para que conversas em qualquer inbox com Scout habilitado nasçam `pending` — hoje nenhuma nasce, em nenhum canal, porque `active_bot?` só considera o mecanismo legado `agent_bot_inbox`/Dialogflow.
- [ ] **[Fase 17 — Observabilidade do Scout e Aviso de Handoff ao Cliente](17-observability-and-handoff-notice/spec77.md)** *(gap encontrado no primeiro teste real do MVP — fail-safe sem detalhe nenhum do que falhou, e cliente sem mensagem no handoff)*: instrumentação Langfuse/OTel no `AgentRunner`/`Tools::BaseTool`, reaproveitando a mesma infra (`Integrations::LlmInstrumentation`, `Captain::ToolInstrumentation`) que o Captain já usa — sem UI/endpoint novo; mensagem pública de transferência antes do handoff (fail-safe e `handover_to_human`), hoje ausente nos dois caminhos, mesmo padrão do Captain (`hook_execution_service.rb#perform_handoff`).
- [ ] **[Fase 18 — Correspondência Desfecho-Estágio no Funil](18-funnel-outcome-stage-matching/spec79.md)** *(saiu do preview — spec final escrita, aguardando implementação)*: seis diretrizes de prompt em `SystemPromptsService` (comparar desfecho vs. descrição de estágio; nunca alegar falta de ferramenta para registrar dado de qualificação; no máximo uma pergunta por resposta; sempre fechar com pergunta de avanço; nunca narrar ações internas de CRM ao cliente; nunca recitar valores permitidos como menu) mais uma dica cosmética de UI no campo de descrição de estágio — resolve as três evidências principais (desqualificação silenciosa, qualificação sem transição, handoff prematuro por crença equivocada de capacidade) e quatro dos cinco sintomas adjacentes de momentum conversacional registrados no preview original (`spec-preview.md`, mesma pasta; Sintoma 3 já corrigido em 2026-08-29).
- [ ] **[Fase 19 — Identidade do Contato: Nome Placeholder vs. Nome Real](19-contact-identity-and-conversation-labeling/spec81.md)** *(saiu do preview — spec final escrita, aguardando implementação)*: contato do widget do site sem nome informado recebe um nome gerado automaticamente (`Haikunator.haikunate(1000)`, `ContactInboxWithContactBuilder#contact_name`, formato `adjetivo-substantivo-número`), mas o Scout nunca questiona isso nem pergunta o nome real por educação (confirmado em duas conversas reais); solução: novo `Custom::Scout::ContactIdentityService` (helper determinístico isolado do model core `Contact`, detecta o padrão só possível no site) + aviso condicional em `SystemPromptsService#context_section` + novo bullet de guardrail (julgamento do modelo) para canais como WhatsApp/Instagram, sem sinal determinístico + reuso do `update_contact` já existente para persistir. Tema original 2 (tool `add_label_to_conversation`) foi descartado do escopo — sem motivação de negócio; registro mantido em `spec-preview.md`.
- [ ] **[Fase 20 — Mensagem de Handoff Natural e Contextual](20-automatic-handoff-reevaluation/spec80.md)** *(saiu do preview — spec final escrita, aguardando implementação)*: a mensagem pública de transferência hoje é sempre o mesmo texto fixo (`I18n.t('conversations.scout.handoff')`), em qualquer um dos dois mecanismos de handoff (decidido pelo LLM ou mecânico da Fase 09), quebrando o tom natural da conversa. A decisão sobre qual mecanismo dispara handoff fica como está (mecânico mantido — determinístico, nunca esquece, protege contra a evidência original da Fase 18); o que muda é que o texto que o próprio modelo escreve no turno passa a virar a mensagem pública (nunca as duas juntas, nunca descartado por padrão), com uma nova diretriz de prompt instruindo uma mensagem de encerramento natural (sem pergunta) sempre que o turno for terminar em handoff — evita reabrir o bug "pergunta e transfere" sem precisar censurar o texto depois. Preview original em `20-automatic-handoff-reevaluation/spec-preview.md`.
- [ ] **[Fase 21 — Unificar Campos Obrigatórios de Qualificação (preview)](21-unify-qualification-required-fields/spec-preview.md)** *(duplicação notada ao configurar campos obrigatórios reais no funil de teste)*: existem hoje dois mecanismos sobrepostos de "campo obrigatório" — `ScoutRequiredField` (Fase 09, configurado na aba "Funil e Qualificação" do Scout, checado só no estágio qualificado) e `PipelineStageRequiredField` (recurso core do Kanban, anterior ao Scout, configurado na tela de gestão de estágios, checado incondicionalmente pra qualquer avanço de estágio via `Opportunity#validate_forward_stage_move_requirements`). Os dois já aparecem como seções redundantes no mesmo prompt (`funnel_section`) para o estágio qualificado. Ideia: os campos obrigatórios do Scout passam a ser inferidos do que já está configurado no estágio qualificado (`PipelineStageRequiredField`), em vez de uma config paralela — elimina a tela/model duplicados.
- [ ] **[Fase 22 — Follow-up com Nudges e Handoff de Resgate por Inatividade](22-scout-follow-up-nudges-and-rescue-handoff/spec85.md)** *(spec final escrita, aguardando implementação; generaliza e substitui o `Scout::FollowUpJob` previsto na Fase 11)*: `Custom::Scout::FollowUpJob`, rodando em cron, detecta conversas `pending` com o Scout que o contato parou de responder e aplica uma cadência escalonada e configurável (`follow_up_delays_hours`, default `[2, 12, 24]` horas) — até 2 mensagens de reengajamento e, se ainda em silêncio, libera a conversa para um humano movendo a Oportunidade para um novo estágio de resgate configurável (`rescue_stage_id`) — nunca marca a Oportunidade como Perdida por conta própria. Inclui mensagem pública dedicada nesse handoff (tom de continuidade, não de cobrança) e um badge "Scout" no card do Kanban indicando conversas ativamente com o Scout. Corrige, no mesmo escopo, uma janela de corrida no Response Auditor (Fase 12) onde um humano respondendo durante a chamada do auditor podia coincidir com uma resposta do Scout.
- [ ] **[Fase 23 — Reconhecimento de Intenção Fora de Prospecção e Handoff Imediato](23-non-sales-intent-immediate-handoff/spec86.md)** *(spec final escrita, aguardando implementação; próxima entrega via speckit)*: novo guardrail em `SystemPromptsService#guardrails_section` — quando o contato deixa claro que não busca uma nova avaliação/tratamento (já é cliente, tratamento em andamento, reagendamento/cancelamento, reclamação, ou "dúvida rápida" não relacionada), o Scout transfere imediatamente via `handover_to_human` em vez de tentar resolver a questão. Uma eventual ferramenta externa de status de cliente no ERP (`ScoutTool`/`call_custom_api`, Fase 04, configuração do operador, sem código novo) serve só como reforço opcional da decisão — a leitura de intenção continua vindo do julgamento do modelo sobre a fala do cliente, nunca automática por status. O mecanismo reativo do Response Auditor (Fase 12, `out_of_scope_commercial_request`) permanece como rede de segurança complementar.
- [ ] **[Fase 24 — Indicador de Mensagem Não Lida no Card do Kanban](24-kanban-unread-message-indicator/spec87.md)** *(spec final escrita, aguardando implementação; não é uma feature exclusiva do Scout, mas depende diretamente da infraestrutura de broadcast em tempo real da Fase 22)*: ponto piscante (lento, `animate-pulse [animation-duration:3s]`) no card da Oportunidade quando a `active_conversation` tem mensagem incoming não lida (`Conversation#unread_incoming_messages`, core), some em tempo real assim que lida. Generaliza o mecanismo de broadcast criado na Fase 22 para o badge "Scout" (`broadcast_scout_badge_refresh` → `broadcast_kanban_badges_refresh`, cobrindo agora `saved_change_to_agent_last_seen_at?` além de `saved_change_to_status?`) e adiciona um novo `Custom::Concerns::Message` (primeiro deste tipo, já suportado pelo core via `Message.include_mod_with('Concerns::Message')`) para o gatilho de mensagem nova, que nenhuma coluna da própria Conversation reflete.
- [ ] **[Fase 25 — Público-Alvo do Scout (Audience Targeting)](25-scout-audience-targeting/spec88.md)** *(spec final escrita, aguardando implementação; motivada pela necessidade de rollout controlado em produção)*: novo campo `audience` (jsonb, formato flat de condições — mesmo padrão de `Custom::AutomationRules::OpportunityConditionsFilterService` e dos filtros de Contatos/Kanban) no `Scout`, avaliado por um novo `Custom::Scout::AudienceMatcherService` (isolado, não reaproveita o service de automation rules). Gate replicado em dois pontos, espelhando a abordagem do Captain (`Captain::Assistant#engages?`, investigada como referência, não reutilizada) mas usando nossos próprios hooks: `custom/app/models/custom/conversation.rb` (arquivo novo, override de `determine_conversation_status`) e `custom/app/models/custom/message.rb` (estendido, override de `reopen_resolved_conversation`) — contato fora do público-alvo nunca fica `pending` abandonado, a conversa nasce/reabre `open` para a fila humana normal. Escopo restrito a atributos de Contato/Conversa (Oportunidade ainda não existe no momento do gate). UI reaproveita `ConditionRow.vue`/`useContactFilterContext()`, já usados pelos filtros do Kanban — sem componente novo no provider de filtro.
- [ ] **[Fase 26 — Estimativa de Valor da Oportunidade por Interesse](26-scout-opportunity-value-estimation/spec91.md)** *(spec final escrita, aguardando implementação; próxima entrega via speckit)*: `Opportunity#value` hoje só é preenchido manualmente — o parâmetro `estimated_value` de `manage_opportunity` existe mas nunca é usado, então toda oportunidade criada pelo Scout contribui zero pro forecast de vendas. Nova tabela `value_by_interest` (jsonb, por Scout) mapeia opções do atributo de qualificação "interesse" (tipo `list`) a um valor — nunca um número inventado pelo modelo. Um novo classificador de escolha forçada (`Custom::Scout::ReferralInterestClassifierService`, mesmo padrão do `ActionClassifierService` da Fase 12) infere o interesse a partir do conteúdo do anúncio de origem (`campaign_headline`/`campaign_body`/etc., já persistidos pela Fase 02) na criação da Oportunidade, com um resultado distinto de "não identificado" (nunca cai numa opção real só por incerteza) — mapa manual por `campaign_source_id` foi considerado e descartado por causa da volatilidade de campanhas. `Custom::Scout::ValueEstimationService` centraliza a sincronização de valor, reaproveitada tanto na classificação automática quanto na qualificação real da conversa. Puramente interno — sem nenhuma relação com o guardrail de nunca informar preço ao cliente.
- [ ] **[Fase 27 — Remover Lista Duplicada de Conversas no Rodapé do Modal de Oportunidade](27-remove-opportunity-conversation-history-footer/spec92.md)** *(spec final escrita, aguardando implementação; não é uma feature exclusiva do Scout, é uma limpeza de duplicidade de UI no Kanban de Oportunidades)*: a seção "Conversas Associadas" no rodapé de `OpportunityBackfillModal.vue` (`specs/039-multi-conversation-opportunities`) ficou redundante depois que a Fase `15-unified-card-click-and-history-links` (`specs/043-card-click-history-links`, ciclo 11) tornou clicável o histórico completo de conversas ligadas/desvinculadas/transferidas já exibido na aba "Activity" do `OpportunityConversationDrawer.vue` (`OpportunityActivityLog.vue`) — superior à lista simples do modal, que só mostra conversas atualmente ligadas, sem histórico de transferência. Remove só a UI e o código órfão do frontend (computeds/funções/i18n exclusivos do bloco); `associated_conversations` no backend permanece intocado, por seguir usado pelo getter `opportunityByConversationId` (consumido pelo próprio drawer substituto).
- [ ] **[Fase 28 — Remover Switch "Total Display" da Coluna do Kanban](28-remove-kanban-lane-total-display-toggle/spec93.md)** *(spec final escrita, aguardando implementação; não é uma feature exclusiva do Scout, é simplificação de UI no Kanban de Oportunidades)*: o switch `total_display_mode` (`value_sum` vs `count`) na configuração de Estágio do Funil faz o cabeçalho de cada coluna do Kanban mostrar só a soma de valor **ou** só a contagem de cards, nunca as duas juntas — passa a mostrar sempre `"{contagem} • {valor formatado}"` (ex.: `"15 • R$ 15,5 mil"`), reaproveitando sem alteração a resolução de moeda já existente (`pipelineCurrencySetting`/`formatCurrencyAmount`, já aplica `R$`/`$` corretamente). Cutover completo: remove o enum e a coluna `total_display_mode` de `ichatr_pipeline_stages`, o parâmetro no controller, o switch na UI de configuração de estágio e as chaves i18n exclusivas dele — nenhum teste backend cobre o campo hoje.
- [ ] **[Fase 29 — Falso Positivo do Guardrail de Intenção Fora de Prospecção e Precedência da Persona (preview)](29-routine-request-qualification-guardrail-fix/spec-preview.md)** *(regressão da Fase 23 identificada em simulação real, conversas display_id 117 e 118)*: o guardrail "Reconhecimento de intenção fora de prospecção" (Fase 23) confunde uma nova solicitação de consulta/avaliação de rotina — sem problema específico declarado — com "dúvida rápida não relacionada a prospecção", disparando `handover_to_human` prematuro em vez de qualificação normal. Confirmado que ajustar apenas a persona da conta não resolve: `custom_instructions_section` (Fase 08) subordina toda instrução personalizada a "não conflitar com regras de segurança", e o guardrail da Fase 23 vive dentro desse bloco — nenhuma persona pode sobrepô-lo por design. Correção prevista em duas frentes: reformular o guardrail (mantendo-o agnóstico de domínio, sem vocabulário de nicho) e revisar a hierarquia de precedência entre persona e guardrails de roteamento de intenção. Mecanismo reativo da Fase 12 permanece inalterado.
- [ ] **[Fase 30 — Visão Geral do Scout: Métricas-Resumo e Distribuição por Etapa do Funil (preview)](30-scout-overview-metrics-and-funnel-distribution/spec-preview.md)** *(desenhado em sessão de brainstorming completa; especificação final e implementação ficam para `/speckit-specify`)*: novo item "Visão Geral", primeiro filho de `Scout` no sidebar (mesma posição do padrão já usado pelo Captain) — cards de métrica-resumo por Scout (oportunidades atendidas, taxa de qualificação/desqualificação/abandono por inatividade via `rescue_stage_id` da Fase 22, mensagens por conversa) e dois gráficos (`BarChart` de `@chatwoot/viz`, já usado por Captain/Campanhas): distribuição das oportunidades atendidas pelo Scout por etapa do funil completo da conta (snapshot atual, não filtrado por período) e interesse por etapa (opcional, depende de `interest_attribute_definition` da Fase 26; card com call-to-action quando não configurado). Novo serviço `Custom::Scout::AnalyticsService`, agregação sob demanda sobre `Opportunity`/`OpportunityStageChange` existentes — sem novas tabelas, sem jobs de agregação.
- [ ] **[Fase 31 — Visão Geral do Scout: Lista de Conversas Recentes (preview)](31-scout-overview-conversations-list/spec-preview.md)** *(desenhado na mesma sessão de brainstorming da Fase 30, da qual depende; especificação final e implementação ficam para `/speckit-specify`)*: tabela de conversas recentes no rodapé da Visão Geral (não uma tela separada), inspirada em Monitor → Conversations do Botpress e na tela de Analytics de Campanha WhatsApp já existente neste fork (`WhatsAppCampaignAnalyticsPage.vue`/`CampaignDeliveryTable.vue`) — contato, duração, contagem de mensagens e status (qualificado/desqualificado/abandonado/em andamento/**transferido sem oportunidade**, este último em cor neutra: toda transferência bem-sucedida também passa por handoff, então "transferido" nunca é sinônimo de fracasso), com pills de filtro por status e paginação (`PaginationFooter`). Clique na linha abre a conversa real do Chatwoot em nova aba (mesmo padrão de `ReportDrilldownCard.vue#openRecord`), sem reconstrução de visualizador de histórico próprio. Novo serviço `Custom::Scout::ConversationsQuery`.
- [ ] **[Fase 32 — Memória de Contato Como Pretexto Indevido de Handoff (preview)](32-contact-memory-handoff-pretext-guardrail/spec-preview.md)** *(problema real identificado em simulação, conversation_id 71257/display_id 44877 e conversation_id 71392/display_id 45006, conta 2 "Dens Odontologia", Scout "Vitória"; especificação completa e implementação ficam para `/speckit-specify`)*: notas de contato geradas pelo mecanismo de memória (`feature_memory`, Fase 02) são injetadas em `SystemPromptsService#contact_context_section` sem data e sem indicar que vêm de uma conversa anterior já encerrada — o modelo leu uma nota antiga ("já pediu atendimento humano") como pedido ativo e chamou `handover_to_human` no meio de uma qualificação legítima, em vez de seguir o funil até o agendamento; o Auditor de Resposta da Fase 12 não intercepta este caminho porque só enxerga o histórico da conversa atual, nunca a Memória de Contato. Inclui achado adicional fora do escopo principal: nota privada de transferência confirmada íntegra no banco mas não renderizada na timeline do dashboard mesmo após hard reload, candidato a Fase 34.
- [ ] **[Fase 33 — Handoff do Auditor de Resposta: Motivo Ilegível na Nota e Classificação Duvidosa de "Fora de Escopo" (preview)](33-response-auditor-handoff-message-quality/spec-preview.md)** *(problema real identificado em simulação, conversation_id 71393/display_id 45007, conta 2 "Dens Odontologia", Scout "Vitória"; especificação completa e implementação ficam para `/speckit-specify`)*: quando o `ActionClassifierService` (Fase 12) decide o handoff via `ResponseAuditor#execute_handoff`, a nota interna mostra o código cru do enum (`out_of_scope_commercial_request`) sem tradução, e a mensagem pública é sempre o texto fixo genérico — comportamento já documentado como decisão explícita em `spec80.md` (Fase 20, "Fora de escopo"), que esta fase propõe reabrir com evidência nova (lead com dor de dente, já demonstrando intenção comercial válida, classificado como "fora de escopo" só por adiar uma pergunta pontual de agendamento/orçamento — confirmado por dupla chamada concordante do classificador, mesma classe de falso positivo já catalogada para `human_offer_accepted`).
