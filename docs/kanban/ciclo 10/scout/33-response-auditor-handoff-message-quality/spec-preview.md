# Fase 33 — Handoff do Auditor de Resposta: Motivo Ilegível na Nota e Classificação Duvidosa de "Fora de Escopo" (Preview)

**Status**: Preview — problema real identificado em simulação de produção (conversation_id 71393 /
display_id 45007, conta 2 "Dens Odontologia", Scout "Vitória"); especificação completa e
implementação adiadas para o momento oportuno, a critério do operador.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 12 (`12-response-auditor/spec78.md`) — introduziu `ActionClassifierService` e
`ResponseAuditor#execute_handoff`, o caminho tratado aqui. Fase 32
(`32-contact-memory-handoff-pretext-guardrail/spec-preview.md`) — mesmo tema (qualidade de handoff
prematuro), mecanismo de causa raiz diferente, descoberta na mesma sessão de investigação.
**Revisita (parcialmente) decisão de**: Fase 20 (`20-automatic-handoff-reevaluation/spec80.md`) —
spec final já escrita (aguardando implementação) que decide **explicitamente** manter a mensagem
pública fixa neste caminho ("Fora de escopo desta fase", item 2). Esta fase traz evidência real de
produção para reabrir *só esse ponto específico* da decisão — o restante de `spec80.md` (os outros
dois caminhos de handoff) não é afetado.

---

## Contexto: "ainda não quero agendar" vira "fora do escopo comercial"

Conversa real (contato Jhonatha Lima, conta "Dens Odontologia", Scout "Vitória",
conversation_id 71393 / display_id 45007, 22/09 19:50–20:30 UTC, Oportunidade #246):

| Hora (UTC) | Quem | Mensagem |
|---|---|---|
| 20:00:37 | Cliente | "quero atendimento" |
| 20:07:17 | Cliente | "sim quero atendimento" |
| 20:09:16 | Cliente | "estou com dor de dente" |
| 20:09:36 | Vitória | prioriza a dor, pergunta a última visita ao dentista |
| 20:14:24 | Cliente | "6 meses" |
| 20:14:46 | Vitória | pergunta se já fez orçamento em outro lugar |
| 20:15:29 | Cliente | **"ainda não quero agendar"** |
| 20:15:58 | *(nota interna)* | `📋 Transferência para atendimento humano: out_of_scope_commercial_request \| Oportunidade #246 - Atendimento inicial - Jhonatha` |
| 20:16:01 | Vitória | **"Transferindo para que outro agente dê assistência."** |
| 20:17:32 | Cliente | "ok" |
| 20:29:58 | Cliente | "cade o atendimento?" |
| 20:30:01 | Cliente | "que demora" |

O lead abriu pedindo atendimento duas vezes, descreveu dor de dente (urgência clínica real,
`custom_attributes.urgencia == "Crítica (com dor ou desconforto)"` na Oportunidade #246, criada
corretamente pelo `manage_opportunity`), respondeu a todas as perguntas de qualificação — e só
recusou **uma pergunta pontual** (se já tinha orçamento em outro lugar / sinalização de que ainda
não quer marcar). Isso encerrou a conversa com uma nota interna cujo motivo é um código em inglês
ilegível para o time, e uma mensagem pública fria que não reconhece a dor relatada nem o que já foi
registrado — o oposto do padrão de "escuta ativa" que o resto do prompt do Scout exige
(`guardrails_section`, bullet "Confirmação de ação"). Doze minutos depois, o cliente demonstra
frustração real, esperando um humano que não apareceu.

## Evidência do problema

### 1. O motivo cru vaza para a nota interna sem tradução

`Custom::Scout::HandoffService#create_transfer_note`
(`custom/app/services/custom/scout/handoff_service.rb:49-56`) interpola `reason` direto na nota:

```ruby
def create_transfer_note(reason)
  Messages::MessageBuilder.new(
    nil, @conversation,
    { content: "📋 Transferência para atendimento humano: #{reason.presence || 'motivo não informado pelo modelo'}#{opportunity_reference}",
      private: true }
  ).perform
end
```

Quando o motivo vem do `handover_to_human` (tool), `reason` é texto livre já em português, escrito
pelo próprio modelo (ex.: ver Fase 32, "Contato demonstra interesse em trocar prótese..."). Quando
vem do `ActionClassifierService` (`ResponseAuditor#execute_handoff`,
`custom/app/services/custom/scout/response_auditor.rb:134-136`), `reason` é um dos quatro valores
fechados de `Custom::Scout::ActionClassifierSchema::REASONS`
(`explicit_human_request`/`human_offer_accepted`/`repeated_frustration_or_loop`/`out_of_scope_commercial_request`,
`action_classifier_schema.rb:5-10`) — código interno em inglês, nunca pensado para leitura humana,
sem nenhuma etapa de humanização no caminho até a nota. Daí a pergunta do operador ("o que é
isso?"): a nota está tecnicamente correta, só ilegível.

### 2. A mensagem pública fria é comportamento já documentado — e já decidido — em `spec80.md`

Confirmado: o texto "Transferindo para que outro agente dê assistência." é exatamente
`I18n.t('conversations.scout.handoff')` (`config/locales/pt_BR.yml:304`), o fallback genérico.
`ResponseAuditor#execute_handoff` chama `HandoffService.perform(reason: reason)` **sem** `message:`
(`response_auditor.rb:134-136`) — por desenho atual, e a Fase 20 (`spec80.md`, spec final já
escrita, aguardando implementação) documenta essa exata decisão como **fora de escopo**, citação
literal:

> *"`Custom::Scout::ResponseAuditor#execute_handoff` (handoff decidido pelo `ActionClassifierService`,
> Fase 12) continua usando a mensagem fixa [...] — esse handoff é uma decisão independente do texto
> que o modelo escreveu no turno (o classificador lê o histórico da conversa, não a resposta
> rascunhada), então reaproveitar o texto do modelo ali seria incoerente (ele pode não saber que a
> conversa vai ser transferida por esse caminho). Fica registrado aqui como decisão explícita, não
> esquecimento."*

Ou seja: não é um bug de implementação — é a implementação pendente já especificada se comportando
exatamente como planejado. A objeção do `spec80.md` (reaproveitar o texto do modelo seria incoerente
porque ele não sabe que vai ser transferido por este caminho) é sobre depender do texto do modelo —
não se aplica a substituir o texto fixo único por um pequeno conjunto de mensagens fixas
diferenciadas por motivo (sem nenhuma chamada de modelo envolvida): mais humanas que o texto genérico
atual, sem reabrir o risco de resposta desalinhada que motivou manter tudo determinístico neste
caminho — ver decisão de desenho 1 abaixo.

### 3. A classificação em si é duvidosa — mesma classe de falso positivo já catalogada para outro motivo

O critério de `out_of_scope_commercial_request` no prompt do classificador
(`action_classifier_service.rb:63`) é *"A solicitação do cliente está fora do escopo comercial do
assistente e requer intervenção de um vendedor humano."* — sem exemplos e sem âncora de evidência
textual, diferente dos outros três motivos (que têm frases-exemplo ou uma condição concreta
verificável). A instrução "Anti-alucinação" do mesmo prompt só dá âncora concreta para
`human_offer_accepted` ("deve existir uma mensagem anterior do assistente oferecendo transferência
humana, e o cliente aceitando") — nenhuma âncora equivalente existe para `out_of_scope_commercial_request`.

Neste caso, o cliente pediu atendimento duas vezes, descreveu dor de dente e respondeu a todas as
perguntas de qualificação — só hesitou em **uma** pergunta específica (orçamento/agendamento). Isso
não é "fora do escopo comercial" por nenhuma leitura razoável — o próprio guardrail "Respeito ao
ritmo do lead" (`guardrails_section`) já cobre exatamente esse padrão ("vou ver e te aviso" / "depois
eu volto") com a instrução de confirmar educadamente e deixar a porta aberta, sem reintroduzir
perguntas — não com handoff. A classificação foi confirmada por **duas** chamadas independentes
concordantes (`ResponseAuditor#handoff_confirmed?`, temperatura 0.0 e 0.7 — exigência da Fase 12
para reduzir falso positivo de uma única chamada), o que indica um viés sistemático do critério vago
nesse tipo de resposta, não um lance isolado de aleatoriedade do modelo — mesma natureza do padrão
já catalogado no código para `human_offer_accepted` (`response_auditor.rb:49-56`: "cliente
escolhendo uma das opções oferecidas... confirmado 5/5 vezes").

## Decisões de desenho (a confirmar na especificação completa)

1. **Duas versões (pt-BR e en) para as quatro mensagens, seguindo o padrão de i18n já usado pelo
   projeto** (`config/locales/en.yml`/`pt_BR.yml`, mesmas chaves nos dois arquivos, sincronizadas —
   convenção do projeto para strings voltadas ao usuário). Novo namespace
   `conversations.scout.handoff_reasons.<reason>.{note,message}`, ao lado da chave já existente
   `conversations.scout.handoff` (mantida, inalterada, ainda usada pelo fail-safe). Continua 100%
   determinístico — sem chamada adicional de LLM, sem reabrir a objeção do `spec80.md` sobre
   reaproveitar texto do modelo (essa objeção não se aplica aqui, porque nenhum texto do modelo está
   envolvido).

   **Dois idiomas resolvidos por campos diferentes**, porque quem lê cada um é diferente:
   - Mensagem pública → `conversation_locale` (idioma do cliente/conversa) — mesmo campo que
     `HandoffService#send_public_handoff_message` já usa hoje para o fallback genérico.
   - Rótulo da nota interna → `@conversation.account.locale` (idioma padrão da conta/equipe) — quem
     lê a nota é o time interno, não o cliente; pode divergir do idioma da conversa (ex.: conta
     brasileira atendendo um cliente que escreveu em inglês).

   Isso também localiza o prefixo compartilhado de `create_transfer_note` ("📋 Transferência para
   atendimento humano:"/"Oportunidade") — hoje fixo em português para **qualquer** caminho de
   handoff (tool, estágio qualificado, classificador). Efeito colateral desejado, não escopo
   ampliado: sem isso, uma nota com rótulo em inglês ficaria com prefixo em português, misturado.

   Rascunho de conteúdo — pt-BR:

   | `action_reason` | Nota interna | Mensagem pública |
   |---|---|---|
   | `explicit_human_request` | Cliente solicitou atendimento humano diretamente | "Claro, sem problemas! Já vou te transferir para um atendente da nossa equipe, que continua o atendimento com você a partir daqui. Obrigado pelo contato até aqui!" |
   | `human_offer_accepted` | Cliente aceitou oferta de transferência para atendimento humano | "Perfeito! Como combinado, vou te encaminhar agora para um atendente da nossa equipe, que continua o atendimento a partir daqui. Obrigado pela paciência!" |
   | `repeated_frustration_or_loop` | Cliente demonstrou frustração repetida ou a conversa entrou em loop sem avançar — revisar histórico | "Peço desculpas pelo transtorno! Vou te transferir agora para um atendente da nossa equipe, que vai poder te ajudar diretamente a partir daqui. Agradeço muito a sua paciência." |
   | `out_of_scope_commercial_request` | Solicitação fora do escopo comercial do assistente — revisar histórico | "Vou te transferir agora para um atendente da nossa equipe, que está mais preparado para te ajudar com isso. Obrigado pelo contato!" |

   Rascunho de conteúdo — en:

   | `action_reason` | Internal note | Public message |
   |---|---|---|
   | `explicit_human_request` | Customer explicitly requested human support | "Of course, no problem! I'll transfer you now to a member of our team, who'll continue helping you from here. Thanks for reaching out!" |
   | `human_offer_accepted` | Customer accepted the offer to transfer to human support | "Great! As agreed, I'm connecting you with a member of our team now, who'll take it from here. Thanks for your patience!" |
   | `repeated_frustration_or_loop` | Customer showed repeated frustration or the conversation is stuck in a loop — review the history | "I'm sorry for the trouble! I'll transfer you now to a member of our team, who'll be able to help you directly from here. Thank you so much for your patience." |
   | `out_of_scope_commercial_request` | Request outside the assistant's commercial scope — review the history | "I'll transfer you now to a member of our team, who's better equipped to help you with this. Thanks for reaching out!" |

   Opcional, a avaliar na especificação completa: interpolar `%{account_name}` nas mensagens
   públicas (mesmo padrão de interpolação já usado em outras chaves de `pt_BR.yml`/`en.yml`, ex.:
   `%{story_sender}` em `messages.instagram_story_content`) — não essencial, só um refinamento de
   tom.
2. **Reforçar o critério de `out_of_scope_commercial_request` no prompt do classificador**: adicionar
   exemplos e uma âncora de evidência textual equivalente às já existentes para
   `human_offer_accepted`/`explicit_human_request`, e deixar explícito que recusar/adiar **uma**
   pergunta pontual (agendamento, orçamento) não caracteriza, sozinho, saída de escopo quando o
   cliente já demonstrou intenção comercial válida na própria conversa — mesmo princípio já usado no
   guardrail "Reconhecimento de intenção fora de prospecção" (Fase 23) e no ajuste da Fase 29.

## Escopo preliminar (a confirmar na especificação completa)

- `config/locales/en.yml` e `config/locales/pt_BR.yml`: novo namespace
  `conversations.scout.handoff_reasons.<reason>.{note,message}`, quatro motivos × dois campos × dois
  idiomas (decisão 1).
- `custom/app/services/custom/scout/handoff_service.rb` e/ou `response_auditor.rb`: resolver
  `note`/`message` pelo `action_reason`, com locale por campo (`conversation_locale` para a mensagem
  pública, `@conversation.account.locale` para a nota interna); ponto de aplicação exato
  (`HandoffService#create_transfer_note`/`#perform` vs. `ResponseAuditor#execute_handoff`) a decidir
  na especificação completa. Sem dependência de `spec80.md` — caminho e mecanismo totalmente
  distintos (mensagens fixas vs. texto do modelo nos outros dois caminhos).
- `custom/app/services/custom/scout/action_classifier_service.rb`: ajuste do critério/exemplos de
  `out_of_scope_commercial_request` (decisão 2).

## Fora de escopo desta fase (preview)

- Os outros dois caminhos de handoff (`handover_to_human` direto, estágio qualificado) — já
  cobertos por `spec80.md`, sem mudança proposta aqui.
- Qualquer mudança na exigência de dupla confirmação do classificador
  (`ResponseAuditor#handoff_confirmed?`) — mecanismo já validado, mantido.
- A Memória de Contato / Fase 32 — mecanismo de causa raiz totalmente diferente, tratado
  separadamente.
- Investigar por que um atendente humano não respondeu em 12+ minutos após o handoff — questão
  operacional/de escala da equipe, não de código.
- Mudanças de código agora — este documento só registra o diagnóstico para tratamento futuro, a
  critério do operador.
- Chamada adicional de LLM para redigir a mensagem de encerramento neste caminho — considerada e
  descartada em favor do mapa de mensagens fixas (decisão 1); mantém o caminho do classificador
  100% determinístico, sem custo/latência extra e sem risco de resposta desalinhada.

## Testes (rascunho)

- `custom/spec/services/custom/scout/handoff_service_spec.rb` (ou onde o mapa for aplicado): novo
  `it` por `action_reason` cobrindo o rótulo correto na nota interna (`account.locale`) e a mensagem
  pública fixa correspondente (`conversation_locale`), nas duas versões (pt-BR/en); `it` cobrindo
  fallback (motivo desconhecido/nulo) para o texto genérico atual.
- Novo `it` confirmando que `config/locales/en.yml` e `pt_BR.yml` têm exatamente as mesmas chaves
  sob `conversations.scout.handoff_reasons` (paridade de chaves entre os dois arquivos).
- `custom/spec/services/custom/scout/action_classifier_service_spec.rb`: novo `it` cobrindo o
  critério revisado de `out_of_scope_commercial_request` (não dispara para recusa pontual de uma
  pergunta com intenção comercial já demonstrada).
- Verificação comportamental via `Custom::Scout::PlaygroundRunner`: replay da conversa 45007 (lead
  com dor de dente, recusa "ainda não quero agendar" numa pergunta pontual) — resposta esperada
  passa a seguir o guardrail "Respeito ao ritmo do lead" (confirma educadamente, sem handoff) em vez
  de transferir como fora de escopo.

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Uma nota interna de transferência disparada pelo classificador mostra um rótulo legível, em
  pt-BR ou en conforme o idioma da conta, para cada um dos quatro motivos — nunca o código do enum
  cru.
- Uma transferência disparada pelo classificador mostra ao cliente uma das quatro mensagens fixas
  humanizadas correspondentes ao motivo, em pt-BR ou en conforme o idioma da conversa — nunca mais
  o texto único genérico atual, sem nenhuma chamada adicional de LLM nesse caminho.
- `en.yml` e `pt_BR.yml` seguem sincronizados (mesmas chaves nos dois arquivos), mesma convenção já
  aplicada ao restante do projeto.
- Um cliente que recusa/adia uma pergunta pontual de qualificação, tendo já demonstrado intenção
  comercial válida na própria conversa, não é classificado como `out_of_scope_commercial_request` —
  segue o guardrail "Respeito ao ritmo do lead" normalmente.
- Nenhuma regressão nos casos genuínos de `out_of_scope_commercial_request` (cliente já é cliente
  com tratamento em andamento, reclamação, pergunta puramente informativa).

---

> **Nota**: Preview criado a partir de simulação real de teste (conversation_id 71393 / display_id
> 45007, conta 2 "Dens Odontologia", Scout "Vitória"), com os três achados confirmados por leitura
> direta de código (`handoff_service.rb`, `response_auditor.rb`, `action_classifier_schema.rb`,
> `action_classifier_service.rb`) e consulta ao banco de produção (mensagens, Oportunidade #246,
> notas de contato). O achado 2 não é um bug de implementação — é a decisão explícita e já
> documentada da Fase 20 (`spec80.md`) se comportando como especificado; esta fase reabre
> especificamente esse ponto com evidência nova, sem alterar o restante de `spec80.md`. Tratamento
> completo adiado para o momento oportuno, a critério do operador — ver `spec60.md` §11. Próxima
> entrega via speckit, mesmo fluxo das fases 26, 23, 29 e 32.
