# Fase 02 — Card de Dados do ERP no Painel do Contato

**Depende de**: Fase 01 (`01-erp-integration-foundation-and-setup/spec94.md`) — hook do Younus
configurado, `Erp::BaseAdapter`/`Erp::AdapterFactory` existentes.

---

## Objetivo

Com o Younus configurado e habilitado (Fase 01), o agente que abre uma conversa precisa ver, no
painel do contato, um card somente-leitura com os dados desse cliente vindos do ERP — buscados
automaticamente pelo telefone do contato, sem nenhuma ação manual. Esta fase implementa a busca (com
cache do vínculo pessoa-contato, igual ao padrão já usado pelo LeadSquared), o endpoint que expõe isso
ao frontend, e o card em si, incluindo o estado de "não encontrado".

## Contexto de investigação (por que este desenho)

- **Precedente direto de card de dados externos no painel do contato**: `ShopifyOrdersList.vue` busca
  via proxy backend (`Api::V1::Accounts::Integrations::ShopifyController#orders`) sempre que o contato
  muda, renderiza um `AccordionItem` dentro de `ContactPanel.vue`
  (`app/javascript/dashboard/routes/dashboard/conversation/ContactPanel.vue:279-292`). Vamos seguir a
  mesma forma.
- **Precedente direto de cache de ID externo + invalidação/retry**:
  `Crm::BaseProcessorService#get_external_id/store_external_id/clear_external_id`
  (`app/services/crm/base_processor_service.rb:62-87`) guarda o ID do lead em
  `contact.additional_attributes['external']["#{crm_name}_id"]`;
  `Crm::Leadsquared::ProcessorService#with_stale_lead_recovery`
  (`app/services/crm/leadsquared/processor_service.rb:102-113`) já implementa "se o ID guardado falhar,
  limpa e tenta de novo uma vez". Vamos espelhar 1:1, trocando `crm_name` por `erp_name` e a condição
  de "falhou" (erro HTTP no LeadSquared) por "telefone não bate" (decisão do operador para o Younus).
- **API do Younus**: além do endpoint de busca por telefone (`GET /webhook/pessoas`, Fase 01), existe
  `GET https://wfh.ichatr.com.br/webhook/pessoa?idEmpresa=<id>&idPessoa=<id>` — mesmo formato de
  erro/sucesso, busca direta por ID, mais barata que buscar por telefone de novo.

## Decisões de desenho

1. **A lógica de cache/validação/retry é código compartilhado, concreto, na base class**
   (`Erp::BaseAdapter#fetch_data`), não duplicada por provedor — cada adapter só implementa as três
   primitivas (`find_by_id`, `search_by_phone`, `phone_from`). Mesmo nível de reaproveitamento que
   `Crm::BaseProcessorService` já demonstra.
2. **Algoritmo de resolução** (dentro de `Erp::BaseAdapter#fetch_data(contact)`):
   1. Sem telefone no contato → resultado "não encontrado", nenhuma chamada de API.
   2. Existe ID de pessoa em cache (`contact.additional_attributes['external']["#{erp_name}_id"]`) →
      busca por ID (`find_by_id`); se achou **e** o telefone retornado bate com o telefone do contato
      → usa esse dado, fim.
   3. Se o telefone não bateu (ou o ID em cache não retornou nada) → invalida o cache
      (`clear_external_id`) e busca por telefone (`search_by_phone`), **uma única vez**.
   4. Achou na busca por telefone → grava o novo ID em cache (`store_external_id`), usa esse dado.
   5. Não achou → resultado "não encontrado".
3. **Comparação de telefone é por dígitos, não string exata** — `nrTelcelpessoa` do Younus vem sem
   formatação/prefixo de país (`"41996937898"`), enquanto `contact.phone_number` normalmente está em
   E.164 (`"+5541996937898"`). Normalização: remover tudo que não é dígito dos dois lados; se não
   bater, tentar de novo removendo um prefixo `"55"` do lado do Chatwoot antes de comparar (evita
   falso-negativo só por causa do código do país).
4. **Endpoint HTTP é agnóstico de provedor** — o frontend nunca sabe se é Younus ou outro ERP.
   `GET /api/v1/accounts/:account_id/integrations/erp/data?contact_id=X` resolve o hook ERP habilitado
   da conta (seja qual for) e delega pro adapter certo via `Erp::AdapterFactory`.
5. **Resposta com 3 estados explícitos**, não só `data: null` ambíguo:
   `{ status: 'found', data: {...} }` / `{ status: 'not_found' }` / erro HTTP 503 com
   `{ error: '...' }` — o frontend decide a UI (JSON / empty state / erro) sem inferir por ausência de
   campo.
6. **Card é somente-leitura, renderiza o JSON completo sem filtro** (`dados[0]['json']` do Younus) —
   decisão explícita do operador de adiar qualquer mapeamento/filtro de campos para uma fase futura.

## Escopo — User Stories

### US1 — Agente vê os dados do cliente no painel do contato, buscados pelo telefone

Como Agente, ao abrir uma conversa cujo contato tem telefone e existe uma integração ERP habilitada na
conta, vejo um novo item no painel do contato ("Dados do ERP") com o registro completo (JSON) vindo do
Younus, buscado automaticamente pelo telefone do contato.

- `Erp::BaseAdapter#fetch_data(contact)` (algoritmo acima, sem cache ainda existente — primeira busca
  sempre cai no passo "busca por telefone").
- `Erp::Younus::Adapter#search_by_phone(phone)` → `GET /webhook/pessoas?idEmpresa&nrTelcelpessoa`;
  retorna `{ external_id: data['idPessoa'], data: data }` ou `nil`.
- `Erp::Younus::Adapter#phone_from(data)` → `data['nrTelcelpessoa']`.
- `Api::V1::Accounts::Integrations::ErpController#data` (`GET .../integrations/erp/data?contact_id=`):
  acha o hook ERP habilitado (`Current.account.hooks.enabled.find { |h| h.erp_integration? }`), 404 se
  nenhum; resolve o adapter via `Erp::AdapterFactory`; chama `fetch_data(contact)`; responde conforme
  decisão de desenho #5. Erros do adapter (`Erp::AuthenticationError`/`Erp::ApiError`) capturados,
  logados via `ChatwootExceptionTracker`, respondidos como 503.
- `ErpDataCard.vue` (novo, mesma forma de `ShopifyOrdersList.vue`): busca ao trocar de contato, mostra
  `<pre>` com o JSON formatado dentro de um `AccordionItem` (loading / erro / sucesso).
- `ContactPanel.vue`: novo branch `element.name === 'erp_data'`, visível só quando existe um hook ERP
  habilitado na conta (`integrations/getEnabledErpIntegration`, novo getter no store, analogia de
  `getIntegration`).
- Rota nova em `config/routes.rb`, namespace `integrations`, mesma forma do `resource :shopify`.

**Critérios de aceite**:
- Contato com telefone e registro existente no Younus: card mostra o JSON completo retornado (o
  objeto de `dados[0]['json']`, sem o envelope `sucesso/mensagem/quantidade`).
- Sem nenhum hook ERP habilitado na conta: nenhum card aparece (nem chamada ao endpoint).
- Erro 503 do Younus (serviço fora do ar): card mostra estado de erro, não quebra o painel do contato
  nem a conversa.

### US2 — Vínculo pessoa-contato é reaproveitado (cache) e revalidado a cada acesso

Como sistema, depois de encontrar a pessoa no Younus uma vez, quero reaproveitar esse vínculo nas
próximas vezes que a conversa for aberta (busca por ID, mais barata), mas sem confiar cegamente nele:
se o telefone da pessoa não bater mais com o telefone do contato, invalido o vínculo e busco de novo
pelo telefone, automaticamente, sem intervenção do agente.

- `Erp::Younus::Adapter#find_by_id(external_id)` → `GET /webhook/pessoa?idEmpresa&idPessoa`, mesmo
  parsing de erro/sucesso do endpoint plural.
- `contact.additional_attributes['external']["#{Erp::Younus::Adapter.erp_name}_id"]`
  (`"younus_id"`) — mesma chave/formato que `Crm::BaseProcessorService` usa para `leadsquared_id`,
  generalizado por `erp_name`.
- `Erp::BaseAdapter#get_external_id/store_external_id/clear_external_id`: helpers compartilhados,
  cópia adaptada de `Crm::BaseProcessorService`.

**Critérios de aceite**:
- Segunda abertura da mesma conversa (mesmo contato, telefone inalterado): o card carrega usando
  `find_by_id` (não chama `search_by_phone` de novo) — verificável por contagem de chamadas HTTP num
  spec.
- Telefone do contato muda no Chatwoot (ou o `idPessoa` em cache aponta pra outro registro no Younus):
  `find_by_id` retorna um telefone diferente do contato → cache é invalidado, `search_by_phone` é
  chamado uma única vez, e se achar, o novo ID substitui o antigo em `additional_attributes`.
- `find_by_id` retorna "não encontrado" (pessoa removida/mesclada no Younus): mesmo comportamento —
  invalida e tenta de novo por telefone, uma vez.

### US3 — Agente vê um empty state amigável quando o contato não tem registro no ERP

Como Agente, quando o contato da conversa não tem nenhum registro correspondente no Younus (nem por ID
em cache, nem por busca de telefone), vejo uma mensagem clara sugerindo cadastrar esse contato no ERP,
em vez de um card vazio, quebrado, ou um erro genérico.

- `ErpDataCard.vue`: novo estado visual `not_found`, distinto de `loading`/`error`/`success`, com
  texto (i18n, `en.json` + `pt_BR.json`) explicando que nenhum registro foi encontrado e sugerindo o
  cadastro no ERP.
- Contato sem telefone (`contact.phone_number.blank?`): mesmo estado `not_found` (sem tentar nenhuma
  chamada), já coberto pelo algoritmo do `Erp::BaseAdapter#fetch_data`.

**Critérios de aceite**:
- Contato com telefone que não existe no Younus: card mostra o texto explicativo, não um objeto JSON
  vazio nem um ícone de erro.
- Contato sem telefone cadastrado no Chatwoot: mesmo texto explicativo (variação de copy opcional
  mencionando a ausência de telefone, a critério da implementação), sem chamar a API do Younus.

## Fora de escopo

- Filtro/mapeamento de campos do JSON exibido — card mostra o registro completo por enquanto, decisão
  explícita do operador.
- Ação do agente para cadastrar o contato no Younus a partir do Chatwoot (o empty state só sugere, não
  oferece um formulário/ação) — direção contrária de sincronização, fora de escopo desta versão (ver
  Fase 01, Decisão de desenho #5).
- Qualquer indicador em tempo real/websocket quando o registro do ERP muda — a busca é sempre sob
  demanda, ao abrir/trocar de contato, igual ao Shopify.

## Testes

- Spec do `Erp::BaseAdapter#fetch_data` (usando um adapter fake/stub de teste) cobrindo os 5 caminhos
  do algoritmo (decisão de desenho #2): sem telefone, cache válido, cache inválido com sucesso no
  retry, cache inválido sem sucesso no retry, sem cache com sucesso/sem sucesso na primeira busca.
- Spec do `Erp::Younus::Adapter#find_by_id`/`search_by_phone`/`phone_from` com `WebMock`, reaproveitando
  os formatos de resposta da Fase 01.
- Request spec do `ErpController#data`: achou, não achou, sem hook habilitado, erro 503.
- Component spec do `ErpDataCard.vue`: loading, sucesso (JSON renderizado), não encontrado (empty
  state), erro.

## Critérios de aceite (fase)

- Fluxo completo: agente abre conversa → card aparece → mostra dado real do Younus (achado) ou empty
  state amigável (não achado) → nunca trava a UI do painel do contato em caso de erro do ERP.
- Segunda visita ao mesmo contato reaproveita o vínculo em cache quando ainda válido, e se autocorrige
  quando não é mais válido — sem exigir nenhuma ação manual do agente.
