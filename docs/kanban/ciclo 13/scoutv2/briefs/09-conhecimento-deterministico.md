# Fase 09 — Conhecimento Determinístico e Visível (Brief)

**Status**: Pronto para speckit
**Data**: 2026-09-24
**Master doc**: `docs/kanban/scoutv2/design.md` §4.7 (conhecimento), §6 (Fase 4)
**Depends on**: — **independente do caminho crítico** (design §6). A mudança de *quando* consultar a
base (do bullet global para o passo da playbook) pertence ao Brief 04 e não bloqueia este.

---

## 1. Problema

A extração de conhecimento **não é reprodutível**: o mesmo site processado várias vezes gerou 15,
20 e 30 pares Q/A — com `temperature: 0.0` já configurada
(`custom/app/services/custom/scout/knowledge_sources/faq_generator_service.rb:18-19`). O operador não
tem como distinguir "o site mudou" de "o extrator variou", porque a única informação exibida hoje é
um contador solitário de pares.

E há perda silenciosa: o conteúdo é cortado em 12.000 caracteres antes da extração
(`faq_generator_service.rb:4,17`) — a cauda do documento simplesmente não vira conhecimento, sem
aviso.

## 2. Diagnóstico / Causa raiz

Duas causas, ambas no mesmo serviço:

- `faq_generator_service.rb:4` (`MAX_CONTENT_LENGTH = 12_000`) aplicado em `:17`
  (`@knowledge_source.content.to_s.slice(0, MAX_CONTENT_LENGTH)`): corte cego. A fronteira do corte
  se move quando o crawler varia, então o conjunto extraído muda sem o documento mudar. **É
  regressão local do fork**: `Captain::Llm::FaqGeneratorService:12-23` não trunca nada (design §1.3).
- `faq_generator_service.rb:33-43`: **uma única chamada sobre o documento inteiro, sem instrução de
  granularidade ou cobertura** — o mesmo parágrafo pode virar 1 ou 4 pares. O prompt do Captain
  ataca isso por redação (*"Extract ALL substantive information… When combined, the FAQs should
  reconstruct the substantive source content entirely"*); o do Scout tem 8 linhas e nenhuma regra de
  cobertura.

Do lado da exibição: `app/javascript/dashboard/components-next/Scout/pageComponents/ScoutKnowledgeTab.vue`
lista as fontes com status e contagem, mas **não exibe os pares derivados** — o que chega ao modelo
é invisível ao operador.

## 3. Precedente

- **`Captain::Llm::PaginatedFaqGeneratorService`** (upstream,
  `enterprise/app/services/captain/llm/paginated_faq_generator_service.rb:5-6,27-42`): 10 páginas
  por bloco, iterativo, parando quando o modelo devolve `has_content: false`. É o precedente
  upstream exato do movimento "uma chamada por bloco em vez de uma chamada por documento".
  **Reaproveitável:** a estrutura iterativa e a instrução de cobertura. **Não se aplica:** a
  paginação por página de PDF — aqui a fonte majoritária é site, e o bloco é definido por tamanho
  com fronteira de parágrafo.
- **Painel Botpress** (design §2.3): a página indexada mostra conteúdo, `Origin: Web Sync`,
  `Uploaded by: Bot`, `Status: Indexed`, `Last Updated` — e a **única ação é `Delete page`**, não
  editar. Confirma o tratamento de derivado como artefato de build.

## 4. Decisões

| # | Decisão | Justificativa |
|---|---|---|
| 1 | **Extração determinística**: blocos de tamanho fixo respeitando fronteira de parágrafo, sobreposição pequena, uma chamada por bloco | Torna a contagem de pares um instrumento de diagnóstico ("caiu de 40 para 22: o site mudou ou o crawler falhou?") em vez de ruído |
| 2 | `MAX_CONTENT_LENGTH` **eliminado** | Corte cego é regressão local; cauda perdida em silêncio é pior que custo de mais uma chamada |
| 3 | Instrução de **cobertura explícita** no prompt, no modelo do Captain | O prompt atual não pede cobertura, e por isso a granularidade flutua |
| 4 | Dedupe de perguntas quase idênticas entre blocos vizinhos, por **similaridade de embedding** | Consequência direta da sobreposição entre blocos; embedding já existe no pipeline |
| 5 | Parâmetros de chunking são **internos, versionados no código**, não expostos ao usuário | Ajustáveis só por deploy; expor viraria superfície de suporte sem ganho (design §4.7) |
| 6 | Derivado é **somente leitura**; edição só para fonte `kind: faq` (autoral) | Artefato de build se regenera, não se conserta. Reprocessar gera conjunto diferente, então casamento por identidade de par seria código morto (design decisão 11) |
| 7 | Correção de conteúdo derivado errado se faz criando uma fonte `kind: faq` com a resposta certa | Caminho já existente (`scout_knowledge_source.rb:13,23`), autoral e estável, sobrevive a qualquer reprocessamento — zero código novo |

## 5. Escopo preliminar

- `custom/app/services/custom/scout/knowledge_sources/faq_generator_service.rb`: chunking,
  iteração por bloco, remoção do `MAX_CONTENT_LENGTH`, prompt com regra de cobertura, dedupe entre
  blocos vizinhos.
- Persistência dos metadados por fonte: `last_extracted_at`, tamanho capturado, contagem de pares.
- API de fontes de conhecimento do Scout: expor os pares derivados por fonte.
- `app/javascript/dashboard/components-next/Scout/pageComponents/ScoutKnowledgeTab.vue`: lista dos
  pares por fonte com `origin`, `last_extracted_at`, status, tamanho e contagem; derivado em modo
  leitura; edição apenas para `kind: faq`.
- i18n `en.json` + `pt_BR.json` para os rótulos novos.

## 6. Fora de escopo

- Re-sync periódico de fonte (equivalente ao `Web Sync` do painel de referência): design §6.4.
- Priorização de par autoral na busca (desempate favorecendo `kind: faq` no top-5): design §6.5,
  com gatilho declarado — par derivado errado atrapalhando na prática.
- Mudança no pipeline de embedding, na busca (cosine, top 5) ou no modelo
  `ScoutKnowledgeEmbedding`: migra inteiro, sem mudança (design §4.7).
- Edição de par derivado: explicitamente rejeitada (decisão 6).
- Mudança no *quando* consultar a base (bullet global → passo da playbook): brief 04.

## 7. Critérios de aceite (rascunho)

### US1 — Extração por blocos, sem corte cego

- Documento maior que 12.000 caracteres tem **todo** o conteúdo processado; nenhuma parte é
  descartada silenciosamente.
- O conteúdo é dividido em blocos de tamanho fixo respeitando fronteira de parágrafo, com
  sobreposição pequena, e cada bloco gera uma chamada de extração.
- O prompt de extração exige cobertura do conteúdo substantivo do bloco.
- `[A CONFIRMAR: tamanho de bloco e sobreposição — o design fixa a política, não os números]`

### US2 — Mesma fonte, mesma contagem

- Reprocessar a mesma fonte sem alteração de conteúdo produz o **mesmo número de pares** (é a prova
  declarada da Fase 4 no design).
- Perguntas quase idênticas geradas por blocos vizinhos por causa da sobreposição são deduplicadas
  por similaridade de embedding, sem remover pares genuinamente distintos.
- `[A CONFIRMAR: limiar de similaridade para dedupe]`

### US3 — O operador vê o que chega ao modelo

- A tela de conhecimento do Scout lista os pares Q/A derivados de cada fonte.
- Cada fonte exibe `origin`, `last_extracted_at`, status, tamanho capturado e contagem de pares —
  substituindo o contador solitário de hoje.
- Par derivado é somente leitura (sem ação de editar); par de fonte `kind: faq` é editável.
- Todos os rótulos novos existem em `en.json` e `pt_BR.json`.

## 8. Testes (rascunho)

- `custom/spec/services/custom/scout/knowledge_sources/faq_generator_service_spec.rb`: documento
  acima de 12.000 caracteres processado inteiro; número de chamadas por bloco; dedupe entre blocos
  vizinhos; mesma entrada → mesma contagem com o cliente LLM dublado deterministicamente.
- `app/javascript/dashboard/components-next/Scout/pageComponents/specs/ScoutKnowledgeTab.spec.js`:
  render dos pares e dos metadados; ausência de ação de edição em par derivado; presença em
  `kind: faq`.

---

> **Nota de proveniência**: decomposto de `docs/kanban/scoutv2/design.md` §4.7 e §6 (Fase 4); a
> variação de 15/20/30 pares na mesma fonte e o corte em 12.000 caracteres
> (`faq_generator_service.rb:4,17`) foram medidos durante o design; o contraste com
> `Captain::Llm::FaqGeneratorService:12-23` está no §1.3.
> Próximo passo: próxima entrega via speckit (`/speckit-specify`).
