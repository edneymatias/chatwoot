# Custo de token vs. fidelidade de teste (Constitution VI/VII/VIII/IX)

**Status**: discussão aberta, sem decisão de mudança de constituição ainda.
**Data**: 2026-09-29
**Contexto de origem**: sessão `/speckit.implement` de `specs/088-scout-v2-first-playbooks` (Fases 7–9,
T081–T097). Este doc não é um brief de feature — é memória de uma discussão de processo/constituição,
para retomar na próxima sessão sem precisar re-explicar o raciocínio.

---

## 1. Gatilho da discussão

Ao final da implementação do spec 088 (12 tarefas de convergência: 5 bugs reais corrigidos + 7 tarefas
de cobertura de teste faltante), o operador observou que a disciplina de TDD/Observable-Behavior tem
encarecido o desenvolvimento em **tokens** (não tempo/processamento) e perguntou se a Constitution
Principle VII (Observable Behavior / Mutation Resistance — nunca mockar o componente sob teste) deveria
ser removida, já que sem essa disciplina "os resultados vinham mais rápido, com o drawback de que muito
provavelmente os testes não testavam nada, eram mocks".

Pergunta em aberto que ficou no ar: **como calibrar o meio-termo, sem voltar a testes que não pegam bug
real?**

## 2. Evidência da própria sessão

### 2.1 Volume de execuções de verificação

Contagem das invocações de `rspec`/`rubocop`/`rails runner` na sessão de convergência (T081–T097):

| Categoria | Nº de execuções | Avaliação |
|---|---|---|
| Ciclo red→green legítimo (T087/T088/T089/T093/T094, batched num único edit de `turn_runner.rb`+`escalation.rb`) | 2 | Necessário — piso do TDD |
| Regressão em árvore completa (`scout_v2` unit tree, arquivos-alvo do quickstart, suíte final) | ~6 | Necessário — exigido pela VII, não é desperdício |
| RuboCop (inicial, autocorrect, recheck) | 3 | Podia ser 1 rodando `-a` direto na primeira vez |
| Isolamento de "isso já estava quebrado antes de mim?" em `playground_messages_controller_spec.rb` | ~8 | Inflado — ver 2.2 |
| Depuração de bug no próprio teste (objeto `conversation` obsoleto em memória) | 4 (2 `rails runner` + 1 rodada com `puts` de debug + 1 final) | Clássico loop edit→test→edit |

Total real: ~23 rodadas de rspec + 3 de rubocop + 2 scripts avulsos de `rails runner`.

### 2.2 Causa raiz do inchaço (não é a VII)

- **`git checkout` como baseline de isolamento sem checar se a árvore era commitada.** A árvore inteira
  do spec 088 estava (e está) não commitada — 34 arquivos modificados + dezenas de novos sem `git add`.
  `git checkout -- turn_runner.rb` devolveu a versão do commit do spec **085**, várias features atrás,
  não o estado real de "início desta sessão". Uma rodada inteira de rspec foi analisada em cima dessa
  base errada antes do erro ser percebido. Correção: reconstruir o arquivo pré-sessão a partir de uma
  leitura própria já feita (que eu já tinha), não do git, quando a árvore não tem commit de referência.
- **Bug de dirty-tracking do ActiveRecord no próprio teste novo** (`custom/spec/jobs/custom/scout/process_message_job_spec.rb`,
  teste "US3-AS9/SC-010"): `conversation.update!(status: :pending)` virou no-op porque o objeto em
  memória já achava que o `status` era `:pending` (valor de criação), sem saber que uma *outra* instância
  do `Conversation` (usada dentro do `TurnRunner`/`HandoffService`) tinha gravado `:open` no banco.
  `save`/`update!` não emite UPDATE para um atributo que a própria cópia em memória já considera
  "atual". Correção: `conversation.reload.update!(status: :pending)`. Custou 2 scripts de depuração via
  `rails runner` (fora do rspec) + 1 rodada instrumentada com `puts` + 1 rodada final limpa.

Nenhuma das duas causas tem relação com "a VII proíbe mock" — são falhas de metodologia de depuração
minhas (do agente), não sintoma da regra.

### 2.3 Onde a fronteira de teste escolhida foi mais cara que o necessário

Isto sim é atribuível à VII **como praticada**, não à VII como regra:

- **T082 (US3-AS3)** — a asserção é puramente sobre decisão de roteamento (`Router.call` pinou ou não
  `agendamento`). Foi implementada como round-trip HTTP completo (`post_message`, resposta do Gemini
  mockada, parse de `system_text`) quando bastaria:
  ```ruby
  ctx = RoutingSnapshot::Builder.call(conversation:, catalog:)
  decision = Router.call(ctx, catalog)
  expect(decision.playbook&.name).not_to eq('agendamento')
  ```
  Mesmo componente real, zero mock do SUT, sem precisar de Rack, parse de JSON do Gemini, ou boot de
  controller — a "porta de entrada mais externa" não era necessária porque a pergunta não é sobre
  fiação (wiring), é sobre uma decisão de uma classe.
- **T095/T096** — dois testes quase idênticos (`fora_de_prospeccao` com `identificacao` pinado vs. com
  `qualificacao` pinado), cada um com dispatch HTTP/job independente e setup completo, onde um teste
  parametrizado ou reaproveitamento de setup teria dado a mesma cobertura por menos boot de Rails.

### 2.4 Onde o ruído de infraestrutura pesou sem comprar nada

Toda rodada trazia dezenas de linhas repetidas de `DEPRECATION WARNING: Defining enums with keyword
arguments...` (uma por model carregado) e backtraces de 10+ linhas de dentro de gems (`climate_control`,
`webmock`) mesmo em falhas triviais. Isso é ruído puro — zero relação com mutation resistance — e foi
mitigado só reativamente com `grep -v DEPRECATION` depois do fato, já pago o custo de receber o texto.

## 3. Análise: VII não é o problema, a fronteira escolhida é

**Separação de eixos**:
- VII governa o **conteúdo** do teste (não mockar o SUT, só a fronteira externa real — provider HTTP,
  exportador OTel).
- A skill `minimizing-test-reruns` (`.agents/skills/minimizing-test-reruns/SKILL.md`, referenciada pelo
  `AGENTS.md` mas fora do catálogo de skills carregado automaticamente — **não foi consultada nesta
  sessão**, e deveria ter sido) governa a **cadência**: quantas vezes você invoca o teste caro durante um
  ciclo de edição.

Essas duas coisas não competem — a VII, ao proibir o atalho de mockar o SUT, é exatamente o motivo pelo
qual desperdiçar rodadas fica caro (cada rodada exige boot completo do Rails + WebMock real, ao invés de
milissegundos de um mock). Remover a VII barateia o custo por rodada destruindo a garantia que ela
existe para dar — 5 bugs de produção reais desta sessão (T087, T088, T089, T093, T094) só ficaram
visíveis porque o teste de aceitação batia no `TurnRunner` real; um mock do componente sob teste teria
"passado" contra a versão quebrada.

O que de fato varia — e onde há espaço real de calibração sem abrir mão de nada — é: **qual fronteira
real** a asserção precisa. Nem toda asserção precisa da fronteira mais externa (HTTP/controller/job).
Fronteira de serviço (`Router.call`, `RoutingSnapshot::Builder`, chamar `TurnRunner#perform` direto sem
Rack) ainda é 100% real, ainda pega mutação, e custa uma fração do entendimento/boot que a fronteira HTTP
exige.

## 4. Alavancas propostas (nenhuma delas reabre a porta pra mock do SUT)

1. **Calar ruído de infraestrutura no ambiente de teste** — silenciar
   `DEPRECATION WARNING` de enum (`ActiveSupport::Deprecation.behavior = :silence` ou equivalente em
   `rails_helper.rb`) e preferir `--format progress` como padrão, só subindo para `documentation`/
   backtrace completo quando uma falha específica precisa de detalhe. Custo zero em qualidade, ganho
   imediato em token por rodada.
2. **Escolher a fronteira real mais barata suficiente para cada asserção** — chamada de serviço para
   lógica de roteamento/predicados; chamada direta de `TurnRunner#perform` (sem HTTP/controller) para
   comportamento de turno; reservar o teste HTTP/job completo para **provar a fiação** (que a decisão
   realmente chega ao prompt renderizado, ao conjunto de tools, ao estado persistido) — tipicamente 1–2
   testes de aceite por user story, não um por variação de cenário.
3. **Aplicar de fato a skill `minimizing-test-reruns`** — ler e citar o arquivo antes de qualquer ciclo
   de convergência/depuração multi-arquivo; planejar tudo, editar em lote, rodar vermelho uma vez, verde
   uma vez. Isso não muda o que é testado, muda quantas vezes o boot do Rails é pago para verificar a
   mesma coisa.
4. **Consolidar testes de aceite quase-duplicados** — parametrizar ou reaproveitar setup entre variações
   próximas (ex.: T095/T096) em vez de round-trips HTTP independentes para cada uma.

## 5. Questão em aberto para a próxima sessão

Vale emendar o texto da Constitution VII no `plan.md`/constituição do projeto para deixar explícito que
"não mockar o componente sob teste" **não** implica "sempre pela porta HTTP mais externa" — algo como:
*"a fronteira pode ser o entry point real (HTTP) ou qualquer seam interno real suficiente para provar a
asserção (ex. chamar `Service.call`/`TurnRunner#perform` diretamente); prefira a fronteira real mais
barata suficiente, escale para o entry point completo só para prova de fiação/aceite"*? Isso formalizaria
a alavanca 2 como regra, não como bom senso ad-hoc do agente. Discutir com o operador antes de editar
qualquer doc de constituição.

Também em aberto: se vale adicionar `ActiveSupport::Deprecation.behavior = :silence` (ou filtro
equivalente) a `spec/rails_helper.rb`/`spec/spec_helper.rb` como mudança de infraestrutura de teste
(alavanca 1) — implementação trivial, mas é uma mudança de config de ambiente de teste compartilhada por
toda a suíte, não só pelo Scout V2, então merece aprovação explícita antes de aplicar.
