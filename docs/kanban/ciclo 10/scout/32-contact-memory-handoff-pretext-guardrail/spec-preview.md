# Fase 32 — Memória de Contato Como Pretexto Indevido de Handoff (Preview)

**Status**: Preview — problema real identificado em simulação de produção (conversation_id 71257 /
display_id 44877 e conversation_id 71392 / display_id 45006, conta 2 "Dens Odontologia", Scout
"Vitória"); especificação completa e implementação adiadas para o momento oportuno, a critério do
operador.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 02 (`02-native-tools-and-pipeline/spec63.md`) — introduziu `feature_memory` e o
mecanismo de memória de contato (`Custom::Scout::ContactNotesService` → `contact.notes` →
`LlmFormatter::ContactLlmFormatter`, espelhando `Captain::Llm::ContactNotesService`), cujo uso
indevido é o objeto desta fase. Fase 12 (`12-response-auditor/spec78.md`) — o auditor de resposta
não intercepta este cenário; ver evidência 4 abaixo. Fase 14
(`14-opportunity-continuity-detection/spec75.md`) — trata a "memória de contato já existente" como
mecanismo estabelecido ao lado do qual injeta contexto de oportunidades abertas; esta fase refina o
mesmo mecanismo, não o substitui. Relacionado, mas **causa raiz distinta** (sintoma-irmão, não
duplicata): Fase 23 (`23-non-sales-intent-immediate-handoff/spec86.md`) e Fase 29
(`29-routine-request-qualification-guardrail-fix/spec-preview.md`) — ambas tratam de outro bullet de
guardrail ("Reconhecimento de intenção fora de prospecção") disparando `handover_to_human` prematuro
por ambiguidade textual; esta fase é sobre a **Memória de Contato** (`contact.notes`) sendo lida
como sinal ativo, um mecanismo de prompt completamente diferente.

---

## Contexto: consulta de teste vira handoff prematuro ao invés de agendamento

Reproduzido ao simular duas sessões de teste reais com o mesmo contato (Edney Matias, conta "Dens
Odontologia", Scout "Vitória"):

1. **Conversa 44877 (19/09, 01:15–01:38 UTC)**: o lead pergunta o endereço da clínica e, em seguida,
   pergunta explicitamente **"Posso falar com um humano?"**. O Scout transfere corretamente
   (`handover_to_human`, motivo `Cliente solicitou atendimento humano direto`). Comportamento
   correto — o pedido está no texto desta própria conversa.
2. **Conversa 45006 (22/09, 19:42–20:00 UTC), três dias depois**: o mesmo contato inicia uma
   conversa nova. Ele nunca pede atendimento humano — ao contrário, engaja normalmente ("então,
   trabalham com próteses?" → "quero trocar a minha prótese." → "já é velha, tá frouxa né, queria
   fazer novo."), com a Oportunidade #245 já criada corretamente pelo `manage_opportunity`. Ao
   responder de forma vaga sobre a última visita ao dentista ("há, ixi, vida corrida." / "nem
   sei."), o Scout chama `handover_to_human` e encerra a conversa citando, na própria mensagem
   pública ao cliente: *"Como você tem interesse em trocar a prótese e **já tinha pedido para falar
   direto com alguém da equipe**, vou deixar seu atendimento agora com um atendente humano [...]"* —
   referenciando o pedido da conversa 44877, três dias e uma conversa inteira encerrada antes.

## Evidência do problema

### 1. A nota de memória gerada pela conversa 44877

Ao final do handoff da conversa 44877, `Custom::Scout::ContactNotesService#generate_and_update_notes`
(disparado por `HandoffService#generate_contact_memory`,
`custom/app/services/custom/scout/handoff_service.rb:13`, porque `scout.feature_memory? == true`)
gravou, entre outras, a nota de contato (`Note#id` 43, `created_at` 2026-09-19 01:22:23 UTC):

> *"Solicitou explicitamente falar com um atendente humano, indicando preferência por atendimento
> humano para dar continuidade."*

### 2. A nota chega ao prompt da conversa nova sem data e sem indicar que já foi resolvida

`Custom::Scout::SystemPromptsService#contact_context_section`
(`custom/app/services/custom/scout/system_prompts_service.rb:96-102`) injeta
`"Contexto do Contato:\n#{@contact.to_llm_text}"` em toda nova conversa do contato.
`LlmFormatter::ContactLlmFormatter#build_notes` (`app/services/llm_formatter/contact_llm_formatter.rb:19-21`,
upstream, compartilhado com o Captain) despeja **todas** as `Note` do contato como uma lista plana:

```ruby
def build_notes
  @record.notes.all.map { |note| " - #{note.content}" }.join("\n")
end
```

Sem data, sem indicar de qual conversa/quando cada nota veio, e sem nenhuma instrução no prompt do
Scout (`guardrails_section`/`contact_context_section`) dizendo como interpretar essas notas. O
modelo recebe a nota #43 na conversa 45006 como se fosse um fato do momento, não um evento já
concluído três dias antes.

### 3. A ferramenta chamada é `handover_to_human`, não o classificador da Fase 12

Confirmado por eliminação, comparando o conteúdo persistido com os três caminhos de handoff
possíveis:

- **Não é o fail-safe** (`AgentRunner#perform_fail_safe_handoff`): usa sempre o texto fixo de
  `I18n.t('conversations.scout.handoff')` (`"Transferindo para que outro agente dê assistência."`,
  `config/locales/pt_BR.yml:304`) — não bate com a mensagem detalhada e contextual enviada.
- **Não é o `ActionClassifierService` da Fase 12** (`ResponseAuditor#execute_handoff`,
  `custom/app/services/custom/scout/response_auditor.rb:134-136`): chama `HandoffService.perform`
  sem `message:`, caindo no mesmo texto fixo acima — também não bate. Além disso, o motivo
  persistido na nota privada ("Contato demonstra interesse em trocar prótese e já havia pedido
  atendimento humano anteriormente...") é texto livre, incompatível com os quatro valores fechados
  de `action_reason` do classificador (`explicit_human_request` / `human_offer_accepted` /
  `repeated_frustration_or_loop` / `out_of_scope_commercial_request`,
  `custom/app/services/custom/scout/action_classifier_schema.rb`).
- **É o caminho 1** (`Custom::Scout::Tools::HandoverToHuman` → `AgentRunner#trigger_handoff`,
  `custom/app/services/custom/scout/agent_runner.rb:119-125`): usa `message: reply_text` (o texto
  que o próprio modelo redigiu) e `reason: tool.handoff_reason` (texto livre do parâmetro `reason`
  da tool, `custom/app/services/custom/scout/tools/handover_to_human.rb:8`) — os únicos dois campos
  que batem exatamente com o observado.

Ou seja: o próprio modelo principal, com acesso à Memória de Contato no prompt, decidiu sozinho
chamar `handover_to_human` citando a nota antiga como parte do motivo.

### 4. Por que o Auditor de Resposta (Fase 12) não bloqueou isso

`ResponseAuditor#evaluate_action` (`response_auditor.rb:57-59`) pula o classificador quando uma tool
já sinalizou `handoff_needed` no turno (`return nil if @handoff_already_flagged`) — por desenho,
para não competir com um handoff já certo via tool (ver comentário em
`response_auditor.rb:46-56`). Mesmo se rodasse, o classificador da Fase 12
(`Custom::Scout::ActionClassifierService`) só recebe o histórico de mensagens **desta conversa**
(`AgentRunner#audit_message_history`) — nunca vê a Memória de Contato. O gap está inteiramente no
prompt principal (`SystemPromptsService`), não em nenhum dos dois auditores.

### 5. Efeito de loop de reforço

O próprio handoff indevido da conversa 45006 gerou, via `HandoffService#generate_contact_memory`,
novas notas — entre elas (`Note#id` 52, `created_at` 2026-09-22 20:00:07 UTC): *"Prefere atendimento
humano: já havia solicitado explicitamente falar com atendente e a conversa atual foi encaminhada
para humano [...]"*. Sem correção, cada handoff indevido fabrica mais "evidência" textual para o
próximo — a tendência piora a cada nova conversa do mesmo contato, não se autocorrige.

## O uso correto da memória (comportamento desejado, já funcionando em parte)

A saudação inicial da própria conversa 45006 (19:42:46 UTC) já usa a memória do jeito certo:

> *"Vi que você já pediu antes o endereço da nossa unidade [...]. Você gostaria só de confirmar
> novamente o endereço/localização da clínica ou já está pensando em vir para uma avaliação
> odontológica?"*

Lembrar de um pedido antigo para **se antecipar proativamente** ("será que agora ele quer avançar
com isso?") é o comportamento correto e não deve ser suprimido. O problema é estritamente o segundo
uso — memória como evidência suficiente, por si só, para justificar handoff no turno atual. A
correção precisa distinguir os dois: manter memória como gancho de personalização/antecipação
proativa (inclusive para puxar o lead direto para agendamento), eliminar memória como pretexto de
handoff.

## Decisões de desenho (a confirmar na especificação completa)

1. **Instrução explícita junto à Memória de Contato no prompt**: novo parágrafo em
   `SystemPromptsService#contact_context_section`, no mesmo padrão "aviso just-in-time" já usado
   por `identity_warning`/`phone_request_warning` (mesmo arquivo) — condicionado a
   `@contact.notes.any?`, deixando explícito que: (a) as notas são resumos de conversas anteriores
   já encerradas, não fatos do turno atual; (b) podem/devem ser usadas para personalizar a
   abordagem e antecipar o que o lead provavelmente quer agora (incluindo puxar para agendamento);
   (c) nunca servem, sozinhas, como justificativa para `handover_to_human` — o sinal de handoff
   precisa estar nas mensagens desta própria conversa. Único ponto de entrada onde a Memória chega
   a qualquer prompt do Scout — não precisa duplicar em outro guardrail.
2. **Data nas notas na origem, sem tocar em código upstream**: `ContactNotesService` (`custom/`,
   `contact_notes_service.rb:11-19`) passa a prefixar cada nota persistida com a data de geração
   (ex.: `[22/09/2026] ...`) antes de `@contact.notes.create!`. Como
   `ContactLlmFormatter#build_notes` renderiza `note.content` verbatim, a data aparece
   automaticamente no contexto do modelo sem precisar alterar
   `app/services/llm_formatter/contact_llm_formatter.rb` (upstream, compartilhado com o Captain) —
   alinhado ao princípio de minimização de acoplamento com upstream já registrado em `spec60.md`
   §3.1. Não retroage sobre notas já persistidas (#41–53).

## Escopo preliminar (a confirmar na especificação completa)

- `custom/app/services/custom/scout/system_prompts_service.rb`: novo parágrafo de aviso em
  `contact_context_section`.
- `custom/app/services/custom/scout/contact_notes_service.rb`: prefixo de data em
  `generate_and_update_notes`.
- Revisitar se `ContactNotesService` deveria também **não regravar** uma nota semanticamente
  idêntica a uma já existente (mitigar o loop de reforço da evidência 5), ou se isso é
  over-engineering dado que a instrução do item 1 já deveria neutralizar o efeito — decisão para a
  especificação completa, não pré-julgada aqui.

## Fora de escopo desta fase (preview)

- Qualquer alteração em `app/services/llm_formatter/contact_llm_formatter.rb` ou em qualquer outro
  arquivo upstream/compartilhado com o Captain — ambas as decisões de desenho ficam inteiramente em
  `custom/`.
- `ActionClassifierService`/`ResponseAuditor` (Fase 12) — permanece como rede de segurança
  complementar, sem mudança; o gap é de contexto de prompt, não do auditor.
- Qualquer mudança no guardrail "Reconhecimento de intenção fora de prospecção" — esse é o escopo
  da Fase 29, mecanismo textual diferente.
- Mudanças de código agora — este documento só registra o diagnóstico para tratamento futuro, a
  critério do operador.

## Achado adicional (fora do escopo principal — candidato a fase futura)

Durante a validação desta conversa no dashboard do Chatwoot, a nota privada automática de
transferência (`HandoffService#create_transfer_note`, `handoff_service.rb:49-56`) **não aparece na
timeline da conversa 45006**, mesmo após hard reload — sintoma confirmado visualmente pelo
operador, que já viu esse mesmo tipo de nota renderizar corretamente em outras conversas (antes e
depois da mensagem pública).

Investigação do lado do banco **não encontrou uma causa de dados/backend**: a `Message#id 1407500`
existe, com `conversation_id`/`account_id`/`inbox_id` corretos, `private: true`, conteúdo íntegro,
`status: "read"` (igual à mensagem pública vizinha) — nada de soft-delete ou inconsistência. Uma
amostra de **todas as 4 notas de transferência existentes no sistema** (incluindo a da conversa
44877, que o operador confirma ter visto renderizar) mostra o mesmo padrão em 4/4 casos: a nota
privada tem `created_at` 1–3s **anterior** à mensagem pública vizinha, apesar de ser criada depois
no código (`HandoffService#perform`: mensagem pública primeiro, nota privada depois) — ou seja, essa
inversão de timestamp é sistêmica e normal neste fluxo, não uma anomalia exclusiva desta conversa, e
portanto não explica sozinha por que só esta não renderizou. `ChatwootApp.otel_enabled?` retorna
`true` em produção (mas sem `LANGFUSE_*` configurado via ENV — o provider ativo de OTel não foi
identificado nesta investigação), então a Fase 17 (instrumentação) pode ter um trace da execução,
se o operador quiser investigar mais fundo por ali.

Como a causa mais provável está do lado do frontend (Vue) e não há reprodução ao vivo disponível
nesta sessão de investigação, este achado foi registrado como candidato a uma fase futura — ver
**[Fase 34 — Nota Interna de Transferência Não Renderizada na Timeline do Dashboard (preview)](../34-dashboard-transfer-note-not-rendering/spec-preview.md)**,
onde o registro foi formalizado sem investigação adicional (nenhuma nova ocorrência desde então).
Os próximos passos de diagnóstico originalmente cogitados aqui — reproduzir com DevTools aberto
(Network + console) numa conversa nova, e revisar como o componente de lista de mensagens do
dashboard trata `private: true` combinado com `sender_type: null` (mensagens geradas pelo sistema,
sem usuário/bot autor) — estão detalhados no documento da Fase 34.

## Testes (rascunho)

- `custom/spec/services/custom/scout/system_prompts_service_spec.rb`: novo `it` cobrindo o aviso em
  `contact_context_section` quando o contato tem notas, e sua ausência quando não tem.
- `custom/spec/services/custom/scout/contact_notes_service_spec.rb`: novo `it` cobrindo o prefixo de
  data no `content` persistido.
- Verificação comportamental via `Custom::Scout::PlaygroundRunner` (mesmo padrão das fases
  anteriores): replay da conversa 45006 com a nota #43 presente no contato — resposta esperada
  passa a seguir o funil de qualificação normalmente, sem chamar `handover_to_human`. Replay de um
  pedido de humano genuíno nas mensagens da própria conversa simulada — deve continuar transferindo
  imediatamente, sem regressão.

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Uma nota de memória mencionando um pedido de atendimento humano de uma conversa anterior já
  encerrada não é, sozinha, suficiente para o Scout chamar `handover_to_human` numa conversa nova
  onde o lead não pediu isso.
- O Scout continua livre para usar notas de memória para personalizar saudações e antecipar
  proativamente interesse em agendamento — sem regressão do comportamento já correto observado na
  saudação da conversa 45006.
- Um pedido de atendimento humano genuíno, presente nas mensagens da conversa atual, continua
  resultando em handoff imediato — nenhuma regressão dos caminhos já existentes (Fase 12, tool
  `handover_to_human`).
- Notas geradas a partir deste momento carregam data de origem visível no contexto do modelo.

---

> **Nota**: Preview criado a partir de simulação real de teste (conversation_id 71257 / display_id
> 44877 e conversation_id 71392 / display_id 45006, conta 2 "Dens Odontologia", Scout "Vitória"),
> com diagnóstico de causa raiz confirmado por eliminação contra os três caminhos de handoff
> possíveis (fail-safe, classificador da Fase 12, tool `handover_to_human`) e por consulta direta ao
> banco de produção (mensagens, notas de contato, timestamps). Inclui achado adicional (nota privada
> não renderizada na UI) com causa de backend descartada por amostragem, mas sem causa raiz de
> frontend isolada — formalizado em `34-dashboard-transfer-note-not-rendering/spec-preview.md`.
> Tratamento completo adiado para o momento oportuno, a critério do operador — ver `spec60.md` §11.
> Próxima entrega via speckit, mesmo fluxo das fases 26, 23 e 29.
