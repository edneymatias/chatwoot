# Custo de token vs. fidelidade de teste (Constitution VI/VII/VIII/IX)

**Status**: alavanca 1 (infra de teste) e emenda de Constitution VI (fronteira por claim) aplicadas
em 2026-09-29 com aprovação do operador na mesma sessão. Alavancas 3-4 seguem em aberto.
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

**[Correção 2026-09-29]** Isto foi originalmente atribuído à "VII como praticada". Incorreto: a VII
não diz nada sobre qual camada usar (só restringe doubles e exige asserção sobre estado observável).
O texto que literalmente exigia isso era a **VI**, terceiro bullet: *"every acceptance criterion...
has at least one test exercising the real entry point (an RSpec `type: :request` spec...)"* — um
teste `type: :request` por *acceptance scenario*, não por user story. Emendado (ver seção 5):

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

## 3. Análise: a VI define a fronteira, a VII define o conteúdo — nenhuma das duas "é o problema"

**Separação de eixos**:
- A VI (emendada em 2026-09-29, ver seção 5) governa **qual fronteira** cada acceptance criterion
  exige, a partir da própria claim que ele faz (decisão/efeito/contrato) — antes desta emenda, o
  texto literal exigia `type: :request` por *acceptance scenario*, sem distinguir o tipo de claim.
- VII governa o **conteúdo** do teste (não mockar o SUT, só a fronteira externa real — provider HTTP,
  exportador OTel). Não diz nada sobre qual camada usar — isso nunca foi dela.
- A skill `minimizing-test-reruns` (`.agents/skills/minimizing-test-reruns/SKILL.md`, referenciada pelo
  `AGENTS.md` mas fora do catálogo de skills carregado automaticamente — **não foi consultada nesta
  sessão**, e deveria ter sido) governa a **cadência**: quantas vezes você invoca o teste caro durante um
  ciclo de edição.

Essas três coisas não competem — a VII, ao proibir o atalho de mockar o SUT, é exatamente o motivo pelo
qual desperdiçar rodadas fica caro (cada rodada exige boot completo do Rails + WebMock real, ao invés de
milissegundos de um mock). Remover a VII barateia o custo por rodada destruindo a garantia que ela
existe para dar — 5 bugs de produção reais desta sessão (T087, T088, T089, T093, T094) só ficaram
visíveis porque o teste de aceitação batia no `TurnRunner` real; um mock do componente sob teste teria
"passado" contra a versão quebrada.

O que de fato variava — e o que a emenda da VI agora formaliza como regra — é: **qual fronteira real**
a claim de cada acceptance scenario precisa. Nem toda claim precisa da fronteira mais externa
(HTTP/controller/job). Fronteira de serviço (`Router.call`, `RoutingSnapshot::Builder`, chamar
`TurnRunner#perform` direto sem Rack) ainda é 100% real, ainda pega mutação, e custa uma fração do
entendimento/boot que a fronteira HTTP exige.

## 4. Alavancas propostas (nenhuma delas reabre a porta pra mock do SUT)

1. **[APLICADA 2026-09-29] Calar ruído de infraestrutura no ambiente de teste** — implementado como
   filtro seletivo, não silêncio total, pra não cegar a suíte pra deprecations futuras genuínas:
   - `config/environments/test.rb`: `config.active_support.deprecation` trocado de `:stderr` (todas as
     mensagens) por uma lambda que descarta só `"Defining enums with keyword arguments"` (repetida uma
     vez por model carregado — ~39 arquivos ainda usam a sintaxe `enum campo: { ... }`, removida no
     Rails 8) e encaminha qualquer outra deprecation pra `warn` como antes.
   - `spec/rails_helper.rb`: adicionado `config.filter_gems_from_backtrace('webmock', 'climate_control')`
     ao lado do `filter_rails_from_backtrace!` já existente — corta os frames internos dessas gems que
     apareciam em toda falha dentro de `with_modified_env`/`stub_request`.
   - `--format progress` já era o padrão (nenhum `--format` setado em `.rspec`) — a segunda parte da
     alavanca já estava satisfeita, sem mudança necessária.
   - Medido (`spec/models/` completo, 1126 exemplos, boot que carrega quase todo o grafo de models —
     pior caso de cobertura): saída total caiu de 28.517 para 13.510 bytes, **-52,6%** (~3.750 tokens a
     menos nessa única rodada), zero mudança em exemplos/falhas (1126 exemplos, 16 falhas idênticas nos
     dois lados, pré-existentes e não relacionadas). 37 ocorrências do warning de enum e 16 frames de
     `webmock`/`climate_control` eliminados, 0 restantes. RuboCop limpo nos 2 arquivos
     (`Style/StderrPuts` autocorrigido pra `warn`). Não corrige a causa raiz (os ~39 usos de
     `enum key: {}` continuam obsoletos pro Rails 8) — ver nota na seção 5. Ressalva: 52,6% é o teto de
     uma rodada que toca quase todo o grafo de models; rodadas mais focadas (poucos models) economizam
     proporcionalmente menos, e o ganho é por *processo* (cada `bundle exec rspec` paga de novo) — não
     reduz o número de reruns, que é a alavanca 2-4, o custo estrutural maior segundo a seção 3.
2. **[FORMALIZADA 2026-09-29 — Constitution VI, ver seção 5] Escolher a fronteira real mais barata
   suficiente para cada acceptance scenario, pela claim que ele faz** — decisão/predicado (verbo
   "decide/seleciona/classifica/roteia") prova por chamada direta ao serviço (`Router.call`,
   `RoutingSnapshot::Builder.call`); efeito/persistência cuja claim não depende de transporte prova
   chamando o service/job direto (`TurnRunner#perform` sem Rack); contrato (resposta HTTP, efeito só
   alcançável pelo caminho completo, UI renderizada) exige `type: :request`/job completo/component
   test. Cada user story precisa de pelo menos um teste de contrato provando a fiação ponta a ponta —
   nem todo acceptance scenario precisa de um.
3. **Aplicar de fato a skill `minimizing-test-reruns`** — ler e citar o arquivo antes de qualquer ciclo
   de convergência/depuração multi-arquivo; planejar tudo, editar em lote, rodar vermelho uma vez, verde
   uma vez. Isso não muda o que é testado, muda quantas vezes o boot do Rails é pago para verificar a
   mesma coisa.
4. **Consolidar testes de aceite quase-duplicados** — parametrizar ou reaproveitar setup entre variações
   próximas (ex.: T095/T096) em vez de round-trips HTTP independentes para cada uma.

## 5. Decisões aplicadas nesta sessão (2026-09-29)

**Emenda à Constitution VI** (não à VII — ver correção na seção 2.3/3): o terceiro bullet exigia
`type: :request` por *acceptance scenario*, sem distinguir o tipo de claim. Reescrito em
`.specify/memory/constitution.md` (v1.4.0 → v1.5.0) pra definir o locus pela claim: decisão/predicado
prova por chamada direta ao serviço; efeito/persistência sem dependência de transporte prova chamando
o service/job direto; contrato exige o boundary real (`type: :request`, job, ou component/store test).
Cada user story precisa de pelo menos um teste de contrato provando a fiação ponta a ponta — nem todo
acceptance scenario precisa de um. Razão da emenda registrada inline na Rationale da VI. Isso
formaliza a alavanca 2 (seção 4, item 2) como regra do `spec.md`, não como julgamento ad-hoc do agente
durante a escrita do teste.

**Alavanca 1 (infra de teste)** — aplicada: `config/environments/test.rb` + `spec/rails_helper.rb`
(detalhe e evidência de verificação na seção 4, item 1). Fora do escopo: os ~39 arquivos de model que
ainda usam `enum campo: { ... }` (sintaxe removida no Rails 8) — corrigi-los eliminaria a causa raiz
do warning em vez de só filtrar a mensagem, mas é edição em massa de arquivos upstream (`app/models`,
possivelmente `custom/`/`enterprise/`), fora do escopo de "silenciar ruído de teste"; avaliar como
tarefa dedicada ou parte de um futuro upstream sync.

**Pendente para a próxima sessão**: alavancas 3 (aplicar de fato `minimizing-test-reruns`) e 4
(consolidar testes quase-duplicados) seguem só propostas, sem aplicação nem exemplo concreto ainda.

## 6. Jev (TypeSafe AI) ajudaria a decidir a fronteira? Não, e não é só "baixo volume"

Pergunta revisitada após o método da seção 3/4 ficar decidível: já que classificar um acceptance
scenario em decisão/efeito/contrato virou uma escolha de 3 opções fixas com critério descrito — a
forma exata de um `Choice` do Jev — caberia automatizar essa classificação? Não, por três razões, não
só volume:

1. **Custo marginal já é zero.** Classificar o AS é subproduto do trabalho que o agente já faz ao
   ler o `spec.md` pra escrever `tasks.md` — não é uma decisão isolada que vale a pena tirar do
   raciocínio corrente e mandar pra uma API à parte.
2. **A classificação correta às vezes depende do código, não só do texto do AS.** Saber se "algo entre
   o boundary e o locus importa pra essa claim" (parsing de params, `before_action`, serialização de
   args do job) exige olhar o controller/job real, não só a frase do AS. Um `state` que não incluísse
   esse código daria classificação errada nos casos que mais importam; incluí-lo destrói a premissa de
   "primitivo barato" do Jev.
3. **Regra determinística já resolve com custo zero.** O vocabulário de verbo (decide/persiste/
   resposta da API retorna) é estável e escrito pela mesma convenção de template — um match de
   palavra-chave classifica com precisão perto de 100% sem chamar rede nenhuma. Preferir um
   classificador probabilístico a uma regra fixa quando a regra fixa já resolve é exatamente o
   anti-padrão que a skill `typesafe-ai` desaconselha ("keep known rules... in code").

Nuance honesta: se o projeto crescesse a ponto de ter centenas de ASs com redação livre e ambígua
(não mais seguindo o template estrito do `spec.md`), um `Noul`/`Choice` do Jev alimentado só com o
texto do AS poderia servir como **sugestão de lint** num futuro `/speckit.tasks` — nunca como gate
autoritativo, porque a razão 2 acima (precisa do código) continua valendo. Hoje, com uma dúzia de ASs
por feature e a heurística de verbo cobrindo o caso comum, não há caso de uso real.
