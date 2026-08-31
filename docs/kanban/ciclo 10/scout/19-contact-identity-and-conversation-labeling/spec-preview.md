# Fase 19 — Identidade do Contato & Label de Conversa (Preview)

**Status**: Preview — dois temas registrados a partir de brainstorming, ambos envolvendo lógica
nova (não só ajuste de prompt, por isso não entraram na Fase 18). Especificação completa e
implementação adiadas para o momento oportuno, a critério do operador.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 08 (`08-system-prompt-guardrails/spec71.md`) — `SystemPromptsService`,
onde o contexto de contato é montado. Phase 02 (`02-native-tools-and-pipeline/spec63.md`) —
padrão de `BaseTool`/registro de ferramentas em `AgentRunner#build_tools`.

---

## Tema 1 — Identidade do contato: nome gerado automaticamente vs. nome real

### Evidência que motivou este tema

Teste manual via widget de chat do site: um contato novo, sem nome informado, ganha um nome
genérico do tipo `empty-meadow-50`. O Scout nunca questiona isso — trata o contato normalmente (ou
simplesmente evita usar o nome), sem nunca perguntar como a pessoa se chama, mesmo quando isso
seria natural por educação/cordialidade comercial.

**Segunda ocorrência confirmada** (2026-08-31, `conversation_id` 53 / `display_id` 51): conversa de
qualificação completa e handoff bem-sucedido (facetas, origem Google, agendamento confirmado), mas
o contato permaneceu com o nome `polished-forest-561` (mesmo padrão Haikunator) do início ao fim —
o Scout nunca perguntou o nome em nenhum momento da conversa, mesmo tendo espaço natural para isso
durante a qualificação. Confirma que o gap não é um caso isolado; a evidência foi levantada de forma
independente, sem relação com as Fases 18/20 recém-concluídas no mesmo ciclo.

### Causa raiz identificada

`ContactInboxWithContactBuilder#contact_name` (`app/builders/contact_inbox_with_contact_builder.rb:62-65`,
código core) gera o nome via `::Haikunator.haikunate(1000)` sempre que nenhum nome é fornecido na
criação do contato — caso típico do widget do site, quando o visitante ainda não se identificou.
Formato determinístico e estável (verificado no código-fonte da gem, `haikunator-1.1.1`):
`adjetivo-substantivo-número` (número 0-999), sempre em inglês, sempre minúsculo, delimitado por
hífen.

`Custom::Scout::SystemPromptsService#context_section` injeta `contact.to_llm_text` cru no prompt
(Fase 08) — não há hoje nenhum sinal explícito diferenciando "nome gerado automaticamente pelo
sistema" de "nome real informado pelo cliente ou lido do canal". O modelo recebe `Name:
empty-meadow-50` exatamente como receberia `Name: Maria Silva`.

### Dois casos, duas estratégias de detecção

- **Site (widget)**: determinístico. Dá para checar a forma do nome (`\A[a-z]+-[a-z]+-\d{1,3}\z`,
  checagem de forma, não de lista fechada de palavras — resistente a upgrade futuro da gem) e saber
  com certeza que é um placeholder, nunca digitado pelo cliente.
- **WhatsApp/Instagram/outros canais**: o nome vem do perfil do próprio canal (push name do
  WhatsApp, username do Instagram) — pode ser um nome real, um apelido, um handle
  (`primeirazinha11234`). Não existe sinal determinístico aqui; só dá para tratar via julgamento do
  modelo (mesmo princípio já usado na Fase 18 — sem hardcode de palavras-chave/padrões
  específicos).

### Escopo preliminar (a confirmar na especificação completa)

1. Helper determinístico (ex: `Contact#placeholder_name?` ou serviço equivalente) que detecta o
   padrão Haikunator por forma, usado só para o caso determinístico acima.
2. Novo trecho condicional em `SystemPromptsService` — quando `placeholder_name?`, avisa
   explicitamente o modelo que aquele nome foi gerado automaticamente pelo sistema (não é o nome
   real do cliente, não deve ser usado para tratá-lo), e instrui a perguntar educadamente o nome em
   algum momento apropriado da conversa (o modelo decide o timing, não necessariamente na primeira
   mensagem).
3. Diretriz geral adicional, para todos os canais (sem sinal determinístico): quando o nome do
   contato parecer um identificador/apelido de sistema em vez de um nome de pessoa, o modelo pode
   perguntar educadamente como a pessoa prefere ser chamada — julgamento do modelo, sem lista fixa
   de padrões a detectar.
4. Nenhuma tool nova: assim que o cliente informar o nome, o Scout usa `update_contact` (já
   existente, `custom/app/services/custom/scout/tools/update_contact.rb`) para persistir.

### Fora de escopo desta fase (preview)

- Qualquer mudança em `ContactInboxWithContactBuilder`/geração do nome placeholder — o
  comportamento core continua o mesmo, só passa a ser sinalizado ao Scout.
- Validação/normalização do nome que o cliente informar (aceita qualquer string, mesmo
  comportamento já existente em `update_contact`).
- Detecção determinística para canais além do site — não é tecnicamente possível de forma
  confiável; fica como julgamento do modelo (item 3 do escopo preliminar).

### Critérios de aceite (rascunho, só valem se a fase avançar)

- Contato do site com nome no padrão Haikunator: o Scout, em algum momento apropriado da conversa,
  pergunta o nome educadamente e, ao receber resposta, chama `update_contact`.
- O Scout nunca se dirige ao cliente pelo nome gerado automaticamente (ex.: nunca diz "Olá, Empty
  Meadow!").
- Contato com nome real (não gerado) mantém o comportamento atual — sem pergunta desnecessária.
- Canais como WhatsApp continuam funcionando sem regressão — a diretriz de julgamento do modelo não
  força pergunta quando o nome do canal já parece um nome real.

---

## Tema 2 — Ferramenta nativa: aplicar label à conversa

### Contexto

O catálogo de ferramentas nativas do Captain (`config/agents/tools.yml`,
`enterprise/lib/captain/tools/add_label_to_conversation_tool.rb`) inclui `add_label_to_conversation`
— o Scout não tem equivalente hoje. Levantado junto com uma revisão mais ampla do catálogo de
tools do Captain (ver Nota de fechamento); os outros itens dessa revisão foram descartados do
escopo:

- **`update_priority`**: fora de escopo desta fase, por decisão explícita — não há motivação de
  negócio registrada ainda para o Scout gerenciar prioridade de conversa.
- **Nota no perfil do contato (equivalente a `add_contact_note`)**: **já coberto**, não é gap. Não é
  um "achado incorreto anterior" — `Custom::Scout::ContactNotesService#generate_and_update_notes`
  (`custom/app/services/custom/scout/contact_notes_service.rb:16`) já grava em `contact.notes`
  (perfil do contato, não na conversa), disparado em todo handoff (`HandoffService`/fail-safe) via
  `@scout.feature_memory?`. É automático (uma síntese da conversa inteira via LLM dedicado) em vez
  de sob demanda como a tool do Captain, mas cobre o mesmo destino de dado.

### Escopo preliminar

- Nova ferramenta `Custom::Scout::Tools::AddLabelToConversation` (mesmo padrão de
  `Custom::Scout::Tools::BaseTool` das demais tools), parâmetro `label_name`, reusa
  `conversation.add_labels` — mesmo método core que o Captain já usa
  (`Captain::Tools::AddLabelToConversationTool#add_label_to_conversation`). Aplica só labels já
  existentes na conta (`Label.find_by(title:)`), sem criar labels novas — mesmo comportamento do
  Captain.
- Registro em `AgentRunner#build_tools` e `PlaygroundRunner#build_tools` (mesmo padrão das demais
  tools).

### Fora de escopo desta fase (preview)

- Criação de labels novas via tool — só aplica labels já existentes.
- UI para restringir quais labels o Scout pode aplicar por conta/inbox — todas as labels da conta
  ficam disponíveis, a menos que evidência futura justifique um filtro.
- `update_priority` e qualquer tool de nota no contato — fora de escopo por decisão explícita (ver
  Contexto acima).

### Critérios de aceite (rascunho, só valem se a fase avançar)

- Scout consegue aplicar uma label existente da conta a uma conversa via tool call.
- Label inexistente retorna mensagem amigável ao modelo (não gera exception não tratada).
- Tool registrada tanto em `AgentRunner` (produção) quanto em `PlaygroundRunner` (simulação).

---

> **Nota**: Preview criado a partir de duas linhas de investigação na mesma sessão de
> brainstorming: (1) teste manual do widget do site revelando nome de contato placeholder nunca
> questionado pelo Scout; (2) comparação do catálogo de ferramentas nativas do Captain
> (`config/agents/tools.yml`) contra o catálogo atual do Scout, da qual só `add_label_to_conversation`
> sobrou como gap real — `update_priority` foi descartado por falta de motivação de negócio, e a
> nota de contato já é coberta por `ContactNotesService` (confirmado lendo o código: grava em
> `contact.notes`, não na conversa). Tratamento adiado para o momento oportuno, a critério do
> operador — ver `spec60.md` §11.
