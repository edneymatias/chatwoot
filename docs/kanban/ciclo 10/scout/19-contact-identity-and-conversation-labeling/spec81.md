# Fase 19 — Identidade do Contato: Nome Placeholder vs. Nome Real

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 08 (`08-system-prompt-guardrails/spec71.md`) — `SystemPromptsService`,
onde o contexto de contato e as guardrails são montados. Phase 02 (`02-native-tools-and-pipeline/spec63.md`)
— `update_contact`, tool já existente e reusada para persistir o nome quando informado.
**Precedido por**: `spec-preview.md` (mesma pasta) — registra a evidência (nome gerado via
Haikunator nunca questionado, duas ocorrências reais) e originalmente também um Tema 2 (tool
`add_label_to_conversation`). **Tema 2 foi descartado do escopo desta fase** por decisão explícita
do operador durante o brainstorming desta spec (2026-09-01) — sem motivação de negócio para
adicionar a tool agora. Este documento cobre só o Tema 1 (identidade do contato).

---

## Objetivo

Fechar o gap identificado em teste real: um contato do widget do site que ainda não se identificou
recebe um nome gerado automaticamente pelo sistema (`Haikunator.haikunate(1000)`, formato
`adjetivo-substantivo-número`, ex. `empty-meadow-50`), mas o Scout nunca sinaliza isso nem pergunta
o nome real, mesmo tendo espaço natural para isso durante a qualificação (confirmado em duas
conversas reais, `spec-preview.md`). Nenhuma tool nova — apenas um helper de detecção isolado no
namespace do Scout (sem tocar `Contact`, código core) e dois ajustes de prompt.

## Escopo

### A. `Custom::Scout::ContactIdentityService` (novo)

Serviço stateless, isolado em `custom/app/services/custom/scout/`, sem tocar o model core
`Contact` — alinhado com a política do fork de minimizar alterações em código upstream.

```ruby
# frozen_string_literal: true

class Custom::Scout::ContactIdentityService
  PLACEHOLDER_NAME_PATTERN = /\A[a-z]+-[a-z]+-\d{1,3}\z/

  class << self
    def placeholder_name?(contact)
      return false if contact&.name.blank?

      contact.name.match?(PLACEHOLDER_NAME_PATTERN)
    end
  end
end
```

O padrão checa a *forma* do nome (dois grupos de letras minúsculas separados por hífen, seguidos
de um número de 1 a 3 dígitos) — não uma lista fechada de palavras do Haikunator, então continua
funcionando mesmo que a gem atualize seu dicionário de adjetivos/substantivos. Cobre as duas
evidências reais (`empty-meadow-50`, `polished-forest-561`) e não gera falso positivo em nomes
reais compostos por dois nomes próprios sem número (`Maria Silva`) nem em handles de outros canais
que não seguem essa forma exata (`primeirazinha11234`).

### B. `SystemPromptsService#context_section` — aviso condicional

Resolve o caso determinístico (site). Extrai a linha atual de contexto de contato para um método
próprio, acrescentando o aviso apenas quando o nome é um placeholder:

```ruby
def context_section
  parts = []
  parts << @catalog_instructions if @catalog_instructions.present?
  parts << knowledge_tool_instruction if @knowledge_available
  parts << contact_context_section if @contact.present?
  parts << open_opportunities_section if open_opportunities_section.present?
  parts << out_of_office_notice if @inbox&.out_of_office?

  return nil if parts.empty?

  parts.join("\n\n")
end

def contact_context_section
  text = "Contexto do Contato:\n#{@contact.to_llm_text}"
  return text unless Custom::Scout::ContactIdentityService.placeholder_name?(@contact)

  "#{text}\n\nAVISO: O nome acima (\"#{@contact.name}\") foi gerado automaticamente pelo sistema " \
    'porque o contato ainda não se identificou — não é o nome real do cliente. Nunca use esse valor ' \
    'para se dirigir a ele (ex: nunca diga "Olá, Empty Meadow!"). Em algum momento apropriado da ' \
    'conversa, pergunte educadamente como a pessoa gostaria de ser chamada e, ao receber a resposta, ' \
    'registre com a ferramenta `update_contact`.'
end
```

### C. `SystemPromptsService#guardrails_section` — bullet novo, para todos os canais

Resolve o caso não-determinístico (WhatsApp, Instagram, etc. — nome vem do perfil do canal, pode
ser nome real, apelido ou handle; sem sinal determinístico, fica a julgamento do modelo, mesmo
princípio já usado na Fase 18 de não fixar padrões/palavras-chave no código). Novo bullet inserido
logo após "Esclarecimento":

```
- Identidade do contato: Quando o nome do contato disponível no contexto parecer um identificador de sistema, apelido ou handle em vez de um nome de pessoa (ex.: sequências genéricas, nomes de usuário com números), evite usar esse valor para se dirigir ao cliente e, em algum momento apropriado da conversa, pergunte educadamente como a pessoa prefere ser chamada — sem forçar a pergunta na primeira mensagem, sem repeti-la caso o lead já tenha sido perguntado nesta conversa (ver histórico), e sem incomodar quando o nome disponível já parecer um nome de pessoa real.
```

## Fora de escopo desta fase

- Qualquer mudança em `ContactInboxWithContactBuilder`/geração do nome placeholder — comportamento
  core inalterado, só passa a ser sinalizado ao Scout.
- Validação/normalização do nome informado pelo cliente — mesmo comportamento já existente em
  `update_contact`.
- Detecção determinística para canais além do site — tecnicamente inviável de forma confiável;
  fica a julgamento do modelo (item C acima).
- Qualquer controle de feature flag/toggle por conta ou Scout — comportamento incondicional, na
  mesma categoria das guardrails gerais da Fase 18 (decisão do operador no brainstorming).
- **Tema 2 (tool `add_label_to_conversation`)** — descartado do escopo desta fase (ver nota no
  cabeçalho); evidência e desenho preliminar permanecem registrados em `spec-preview.md` caso volte
  a ser priorizado no futuro.

## Testes

### Specs automatizados (TDD)

- `custom/spec/services/custom/scout/contact_identity_service_spec.rb` (novo): tabela de casos para
  `.placeholder_name?` — positivos (`empty-meadow-50`, `polished-forest-561`, casos de borda como
  número de 1 e 3 dígitos), negativos (`Maria Silva`, `joao123`, `primeirazinha11234`, nome com mais
  de duas palavras, `nil`, string vazia).
- `custom/spec/services/custom/scout/system_prompts_service_spec.rb` (estende o `describe`
  existente de contexto de contato, padrão já usado no arquivo — `expect(prompt).to
  include(...)`/`not_to include(...)`): um `it` confirmando que o aviso aparece quando
  `contact.name` é um placeholder, outro confirmando que não aparece para um contato com nome real.
  Novo `it` em `guardrails_section` confirmando a presença do bullet "Identidade do contato".

### Verificação comportamental

Replay via `Custom::Scout::PlaygroundRunner` da conversa `display_id 51` (Oportunidade #28, segunda
evidência real — qualificação completa sem o Scout nunca perguntar o nome) reconstruindo a mesma
sequência de mensagens: verificar se o Scout agora pergunta o nome em algum momento apropriado e
chama `update_contact` ao receber a resposta. Smoke test rápido, não é garantia de comportamento
100% determinístico (LLM é estocástico) — validação final continua sendo o teste manual do operador
no widget real.

## Critérios de aceite

- Contato do site com nome no padrão Haikunator: o Scout, em algum momento apropriado da conversa,
  pergunta o nome educadamente e, ao receber resposta, chama `update_contact`.
- O Scout nunca se dirige ao cliente pelo nome gerado automaticamente (ex.: nunca diz "Olá, Empty
  Meadow!").
- Contato com nome real (não gerado) mantém o comportamento atual — sem pergunta desnecessária, sem
  o aviso condicional no prompt.
- Canais como WhatsApp continuam funcionando sem regressão — a diretriz de julgamento do modelo não
  força pergunta quando o nome do canal já parece um nome real.
- `Custom::Scout::ContactIdentityService` não é referenciado por nenhum código fora do namespace
  `Custom::Scout` — mudança isolada, sem tocar `Contact` (core).
- Nenhuma regra de negócio (palavra-chave, lista fechada de nomes) fica hardcoded no prompt ou no
  helper de detecção além do regex de forma já especificado.
