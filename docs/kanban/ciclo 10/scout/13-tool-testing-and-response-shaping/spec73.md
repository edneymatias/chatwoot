# Phase 13 — Teste de Requisição & Formato de Saída das Ferramentas Externas

**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Phase 04 (`call_custom_api`/`ScoutTool` — executor de ferramentas REST/webhook
externas, `custom/app/services/custom/scout/tools/call_custom_api.rb`).
**Depended on by**: nenhuma fase posterior depende desta.

## Contexto: o problema identificado

A configuração de ferramentas externas do Scout (`ScoutTool`, tela de gestão em
`app/javascript/dashboard/components-next/Scout/pageComponents/ScoutToolModal.vue`) hoje tem três
lacunas em relação à ferramenta equivalente do Captain (`Captain::CustomTool`):

1. **Sem botão de teste.** O operador só descobre se a URL/headers/payload configurados funcionam
   quando a LLM chama a ferramenta em produção, com um lead real na conversa.
2. **Sem suporte a parâmetros de URL.** `Custom::Scout::Tools::CallCustomApi#execute_request`
   (`custom/app/services/custom/scout/tools/call_custom_api.rb:112-132`) chama sempre a
   `endpoint_url` literal — não existe mecanismo de path params (`/pedidos/{id}`) nem de
   querystring. Pior: para métodos `GET`, o `payload` da LLM é **descartado por completo** —
   `body = (method == :post || payload.present?) && method != :get ? payload.to_json : nil` nunca
   monta corpo para GET, e como não há querystring, o parâmetro simplesmente não chega na API.
3. **Sem formato de saída configurável.** `format_response`
   (`custom/app/services/custom/scout/tools/call_custom_api.rb:171-178`) só faz
   `JSON.parse`-ou-devolve-cru — a LLM sempre recebe o corpo bruto da resposta, mesmo quando a API
   devolve um payload grande e majoritariamente irrelevante para a decisão do agente.

Adicionalmente, ao inspecionar `ScoutToolModal.vue` para esta fase, foi identificado um bug
pré-existente: o formulário envia os campos `url`/`headers` no payload de criação/edição
(`custom/... /ScoutToolModal.vue:93-101`), mas o backend espera `endpoint_url`/`auth_headers`
(`custom/app/controllers/api/v1/accounts/scout_tools_controller.rb`, método `tool_params`) — ou
seja, salvar uma ferramenta hoje nunca grava a URL real nem os headers de autenticação. Esta fase
corrige esse bug junto, por tocar exatamente nesses campos do mesmo arquivo.

## Arquitetura identificada no Captain (referência)

> Leitura de referência apenas — não reaproveitada/copiada como código ou texto de produto (mesma
> ressalva de licenciamento das fases anteriores, ex. Fase 07/08).

Fonte: `enterprise/app/models/concerns/toolable.rb`, `enterprise/lib/captain/tools/http_tool.rb`,
`enterprise/app/controllers/api/v1/accounts/captain/custom_tools_controller.rb`,
`app/javascript/dashboard/components-next/captain/pageComponents/customTool/CustomToolForm.vue`.

- **Templates Liquid estritos para URL e corpo.** `Toolable#build_request_url`/`#build_request_body`
  (`toolable.rb:39-49`) renderizam `endpoint_url`/`request_template` com Liquid quando contêm
  `{{`. `#render_template` (`toolable.rb:110-116`) usa
  `Liquid::Template.parse(template, error_mode: :strict)` +
  `render(..., strict_variables: true, strict_filters: true)` — variável ausente é erro fatal
  (`Liquid::UndefinedVariable`), capturado e relançado como `"Template rendering failed: ..."`.
  Não existe distinção entre "path param" e "query param": tudo que está fora do template vai
  para o corpo (`POST`) ou é simplesmente ignorado (`GET` não tem querystring automática no
  Captain também — o operador embutiria tudo via `{{}}` na própria `endpoint_url`).
- **`response_template` para moldar a saída.** `Toolable#format_response`
  (`toolable.rb:101-106`) só aplica o template se `response_template` estiver preenchido;
  caso contrário devolve o corpo cru. O contexto de renderização expõe o JSON parseado da resposta
  sob duas chaves (`'response'` e `'r'`, atalho), permitindo escrever algo como `{{ r.data.preco }}`.
- **Botão de teste opera sobre rascunho não salvo.** `CustomToolsController#test`
  (`custom_tools_controller.rb:27-32`) instancia `account_custom_tools.new(custom_tool_params)` —
  não precisa salvar antes de testar — e chama diretamente
  `Captain::Tools::HttpTool#execute_http_request` (via `send`, método privado), devolvendo
  `{ status:, body: body.truncate(500) }`. No frontend
  (`CustomToolForm.vue:155-177`), o botão fica **desabilitado** se `endpoint_url` contém `{{` ou
  se `request_template` está preenchido (`isTestDisabled`, `CustomToolForm.vue:157-159`) — ou
  seja, o Captain **não testa** URLs/corpos templados; só testa configurações estáticas simples,
  e só mostra status HTTP no resultado (nunca o corpo da resposta) no componente de UI, embora o
  backend já devolva o corpo truncado.

## Diferenças de contexto: Scout não é Captain

O `ScoutTool` do Scout não tem `request_template` (o corpo da requisição é sempre o `payload` que
a LLM monta a partir do `parameters_schema`, enviado literalmente como JSON — não há template de
corpo). A única coisa que falta templar é a **URL** (path params). Isso simplifica o modelo de
dados: nenhuma coluna nova de template de corpo é necessária, só a URL e, para saída, o
`response_template`.

Diferente do Captain, o Scout precisa resolver explicitamente o caso `GET`: como não existe
`request_template`, e o `payload` da LLM é a única fonte de parâmetros, os campos do `payload` que
não forem consumidos pela URL **precisam** virar querystring em `GET` — sem isso, GET nunca recebe
parâmetro nenhum (bug atual, descrito acima). O Captain não resolve esse caso porque delega tudo
ao operador escrever `{{}}` na própria URL; o Scout, tendo `parameters_schema` como fonte
estruturada de parâmetros, resolve automaticamente sem exigir que o operador escreva a querystring
à mão.

## Escopo

### 1. Path params na `endpoint_url` (Liquid, renderização estrita)

`endpoint_url` pode conter placeholders Liquid (`https://api.com/pedidos/{{order_id}}`). Ao montar
a requisição:

- Extrai-se do texto do template quais chaves do `payload` são referenciadas (parse do template
  Liquid).
- Renderiza-se a URL substituindo essas chaves — **modo estrito**, igual ao Captain
  (`error_mode: :strict`, `strict_variables: true`, `strict_filters: true`): se uma chave
  referenciada na URL não existir no `payload`, a renderização falha, a requisição **não é
  enviada**, e o erro retornado (à LLM, no fluxo real, ou à UI, no teste) é o de falha de
  template — nunca uma chamada HTTP com segmento vazio na URL.
- As chaves do `payload` consumidas pela URL são removidas do conjunto que sobra para o passo
  seguinte.

### 2. Querystring (GET) / corpo (demais métodos) para o que sobrar

As chaves do `payload` **não** consumidas pela URL:
- Se o método for `GET`: serializadas como querystring (`?chave=valor`) — corrige o bug descrito
  no Contexto, onde hoje o `payload` é descartado por completo em GET.
- Nos demais métodos (`POST`, `PUT`, `PATCH`): serializadas como corpo JSON — comportamento já
  existente, preservado.

### 3. `response_template` (Liquid, renderização estrita) para moldar a saída

Nova coluna `response_template` (`text`, opcional) em `ichatr_scout_tools` (migration sob
`custom/`). `ScoutTool#format_response(raw_body)`: se `response_template` estiver em branco,
comportamento atual é preservado (`JSON.parse`-ou-corpo-cru); se preenchido, renderiza o template
(Liquid, mesmo modo estrito acima) com o JSON parseado da resposta disponível sob `response` e `r`
(mesmo atalho do Captain). `Custom::Scout::Tools::CallCustomApi#format_response` passa a delegar
para `ScoutTool#format_response` em vez da lógica inline atual.

### 4. Extração do executor HTTP compartilhado

A lógica de montagem/execução de requisição (itens 1, 2, headers de autenticação, chamada via
`SafeFetch`) sai de dentro de `Custom::Scout::Tools::CallCustomApi` (hoje acoplada a
`RubyLLM::Tool`, `account`, validação de schema) para um serviço plano novo,
`Custom::Scout::Tools::HttpRequestExecutor`, recebendo a configuração da ferramenta (URL, método,
headers, `response_template`) e um `payload`, devolvendo status HTTP + corpo bruto + corpo
formatado. `CallCustomApi#execute` passa a delegar a esse executor depois da validação de schema
(item 5 abaixo, inalterado); o novo endpoint de teste (item 6) usa o mesmo executor diretamente,
sem validação de schema.

### 5. Validação de schema continua exclusiva do fluxo real

`validate_payload_schema` (`call_custom_api.rb:85-...`) continua bloqueando, antes da chamada HTTP,
`payload` que não bate com `parameters_schema` — **mas só no fluxo de execução real pela LLM**. O
fluxo de teste (item 6) não passa por essa validação: o objetivo do teste é ver o comportamento
real da API/URL com o que o operador digitar, incluindo payload incompleto.

### 6. Endpoint de teste

Nova rota `POST /api/v1/accounts/:account_id/scout_tools/test`
(`Api::V1::Accounts::ScoutToolsController#test`), operando sobre configuração de rascunho (não
precisa da ferramenta estar salva — mesmo padrão do Captain, `account.scout_tools.new(tool_params)`).
Recebe a configuração da ferramenta (URL, método, headers, `response_template`) mais um `payload`
de exemplo digitado pelo operador; chama `HttpRequestExecutor` diretamente (sem validação de
schema, conforme item 5); devolve status HTTP + corpo bruto (truncado, mesmo limite de 500
caracteres do Captain) + corpo já formatado por `response_template`, quando preenchido. Erros de
rede/timeout (`SafeFetch::FetchError`) e erros HTTP (`SafeFetch::HttpError`) são capturados e
devolvidos como parte do resultado do teste (status + mensagem), nunca como exceção não tratada —
igual ao padrão de erro já usado em `CallCustomApi`.

### 7. Frontend (`ScoutToolModal.vue`)

- Corrige o bug de nomes de campo: `url`/`headers` → `endpoint_url`/`auth_headers`, alinhando com
  os parâmetros reais aceitos por `ScoutToolsController#tool_params`.
- Novo campo `response_template` (textarea, mesmo estilo `font-mono` usado para o schema JSON).
- Novo campo de payload de exemplo (JSON) + botão "Testar" (mesmo padrão visual do botão de teste
  do Captain: `variant="faded" color="slate" icon="i-lucide-play"`, estado de loading, resultado
  exibido logo abaixo).
- Painel de resultado do teste: status HTTP (sucesso/erro, com cor), corpo bruto e — quando
  `response_template` estiver preenchido — a prévia já transformada, lado a lado, para o operador
  ajustar o template olhando o resultado real da mesma chamada.

## Fora de escopo desta fase

- Suporte a `request_template` (corpo templado) — o corpo do Scout continua sendo sempre o
  `payload` serializado como JSON; não há necessidade identificada de um template de corpo
  separado, diferente do Captain.
- Métodos de autenticação adicionais (`bearer`/`basic`/`api_key` estruturados como no Captain) —
  `auth_headers` do Scout continua sendo um campo livre de headers HTTP; não faz parte desta fase.
- Alteração em `parameters_schema` para marcar explicitamente se um parâmetro é "de URL" ou "de
  corpo/querystring" — a detecção é automática (o que está no template da URL é path param, o
  resto vira querystring/corpo), sem exigir metadado extra no schema.
- Limite de ferramentas por conta (`MAX_PER_ACCOUNT`, existente no Captain) — não identificado como
  necessidade atual do Scout.

## Critérios de aceite

- `CallCustomApi`/`HttpRequestExecutor` resolvem `{{param}}` na `endpoint_url` a partir do
  `payload`, em modo estrito: variável ausente impede o envio da requisição e retorna erro de
  template, nunca uma URL com segmento vazio.
- Requisições `GET` enviam as chaves do `payload` não consumidas pela URL como querystring — o bug
  atual de descarte silencioso do payload em GET deixa de existir.
- `response_template`, quando preenchido, transforma o corpo da resposta antes de chegar à LLM;
  quando vazio, o comportamento atual (JSON parseado ou corpo cru) é preservado.
- Existe um botão de teste na tela de configuração de ferramentas que dispara uma requisição real
  (sem exigir salvar a ferramenta antes), aceita um payload de exemplo digitado pelo operador, e
  mostra status HTTP + corpo bruto + corpo transformado (se `response_template` preenchido) — erros
  da API real (4xx/5xx) aparecem tal como a API os devolveu, não mascarados por validação própria.
- O teste não passa pela validação de `parameters_schema` — só a execução real (chamada pela LLM)
  valida o payload antes de montar a requisição.
- `ScoutToolModal.vue` envia `endpoint_url`/`auth_headers` (não mais `url`/`headers`) ao criar/editar
  uma ferramenta.
