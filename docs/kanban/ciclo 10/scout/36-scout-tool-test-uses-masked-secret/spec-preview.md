# Fase 36 — "Testar" no Editor de Ferramenta Externa Envia o Valor Mascarado do Segredo, Nunca a Credencial Real (Preview)

**Status**: Preview — problema real identificado ao investigar a Fase 35 (conta 1 "Acme Inc"): as 4
`ScoutTool` da conta estavam com `auth_headers` apontando para um token-placeholder de teste
("abobora"), nunca substituído pela credencial real do n8n — causa das falhas 403 vistas nas
simulações. Ao corrigir a credencial diretamente no banco e depois tentar validar pela função
"Testar" do editor de ferramentas no dashboard, o operador reportou que o teste continua retornando
403 a menos que cole a chave manualmente no campo — mesmo a ferramenta já tendo a credencial
correta salva. Especificação completa e implementação ficam para o momento oportuno, a critério do
operador.
**Master doc**: `docs/kanban/ciclo 10/scout/spec60.md` §11 (Roadmap)
**Depends on**: Fase 1 (`01-core-and-data-model/spec62.md`) — introduziu `ScoutTool`. Backlog
[`11-production-secrets-encryption-hardening`](../../backlog/11-production-secrets-encryption-hardening/spec61.md)
— motivou `encrypts :auth_headers` e o mascaramento (`ScoutTool::MASKED_SECRET`) nunca devolver o
segredo em claro ao frontend, comportamento correto que este bug não deve regredir.

---

## Contexto: o mascaramento de segredo (correto) não tem contrapartida no botão "Testar" (bug)

`ScoutTool#masked_auth_headers` (`custom/app/models/scout_tool.rb:54-68`) nunca devolve o segredo
real via API — por design, para não vazar credenciais para o frontend/DevTools. Em troca, o fluxo de
salvar (`update`) sabe reidratar o segredo real quando o campo volta do formulário ainda mascarado:

```ruby
# custom/app/models/scout_tool.rb
MASKED_SECRET = '••••••••'

def apply_credentials_update(incoming_credentials)
  return if incoming_credentials.blank?

  normalized = normalize_incoming_hash(incoming_credentials)
  merge_preserved_secrets(normalized, parsed_auth_headers) # preserva se blank ou == MASKED_SECRET
  self.auth_headers = normalized
end

def secret_blank_or_masked?(val)
  val == MASKED_SECRET || val.blank?
end
```

Isso está coberto por spec e passa hoje (`custom/spec/models/scout_tool_spec.rb:178-188`, "preserves
existing secrets when updating with masked values").

**O endpoint de teste não passa por nada disso.** `ScoutToolsController#test`
(`custom/app/controllers/api/v1/accounts/scout_tools_controller.rb:47-66`) não está na lista
`before_action :set_scout_tool, only: %i[show update destroy]` (linha 5) — ou seja, a action nunca
carrega o `ScoutTool` existente. Ela monta o `HttpRequestExecutor` direto dos parâmetros crus da
requisição:

```ruby
def test
  tp = test_params
  executor = Custom::Scout::Tools::HttpRequestExecutor.new(
    endpoint_url: tp[:endpoint_url],
    http_method: tp[:http_method] || 'POST',
    auth_type: tp[:auth_type] || 'none',
    auth_headers: tp[:auth_headers],   # <- literal do formulário, sem merge com o segredo salvo
    response_template: tp[:response_template],
    payload: tp[:payload]
  )
  result = executor.execute
  ...
end
```

E a rota é `collection` (`config/routes.rb:174-176`, `post :test, on: :collection` — não
`member`/`:id`), então o payload do teste nem carrega o id da ferramenta sendo editada
(`ScoutToolModal.vue:377-405`, `testPayload` só tem `endpoint_url`, `http_method`, `auth_type`,
`auth_headers`, `response_template`, `payload` — nenhum `id`/`tool_id`).

## Reprodução ponta a ponta

1. `GET /scout_tools` ou `/scout_tools/:id` → `format_tool_json` (`scout_tools_controller.rb:79-81`)
   devolve `auth_headers` mascarado, ex. `{"header_name":"token","header_value":"••••••••"}`.
2. Ao abrir "Editar" no modal, o watcher de inicialização (`ScoutToolModal.vue:303-308`) preenche os
   campos de credencial a partir desse valor mascarado — e o próprio fallback do campo, quando o
   valor vem vazio, também é a string mascarada:
   ```js
   bearerToken.value = rawHeaders.token || '••••••••';
   basicPassword.value = rawHeaders.password || '••••••••';
   apiKeyHeaderValue.value = rawHeaders.header_value || '••••••••';
   ```
3. Operador clica "Testar" sem tocar no campo de credencial. `handleTest`
   (`ScoutToolModal.vue:377-405`) monta `auth_headers: compileAuthHeaders()` a partir desses mesmos
   refs (ainda contendo `'••••••••'`) e envia para `POST /scout_tools/test`.
4. `ScoutToolsController#test` repassa esse literal `'••••••••'` como o valor real do header/token
   para `HttpRequestExecutor`, que o envia à API externa real.
5. A API externa rejeita a string mascarada (não é o token verdadeiro) → 401/403 — **independente da
   credencial de verdade estar correta no banco**, reproduzindo exatamente o sintoma relatado: depois
   de corrigir a credencial da conta 1 no banco, "Testar" seguiu dando 403 até colar a chave de novo
   manualmente no campo.

Confirmado por leitura direta do código nos dois lados (controller + `ScoutTool`/`scout_tool.rb`) e
do componente Vue (`ScoutToolModal.vue`), sem necessidade de reproduzir contra uma API externa real —
o caminho dos dados é determinístico: nenhum ponto entre o carregamento do formulário e o disparo do
teste jamais consulta `@scout_tool.parsed_auth_headers`/`auth_headers` reais quando o campo está
mascarado ou vazio.

## Por que isso não é o mesmo bug da Fase 35

Fase 35 é sobre o laço de repair do `ResponseAuditor` vazando narrativa interna durante uma
conversa real do Scout (`response_auditor.rb`) — caminho de execução completamente diferente, sem
relação com o editor de ferramentas do dashboard ou com `ScoutToolsController`. A causa raiz aqui é
puramente de UI/API de configuração (`custom/app/controllers/.../scout_tools_controller.rb` +
`app/javascript/.../ScoutToolModal.vue`), nunca tocada pelo código da Fase 35.

## Decisões de desenho (a confirmar na especificação completa)

1. **Fazer `test` reidratar o segredo real quando o campo enviado está mascarado/vazio**, espelhando
   exatamente `apply_credentials_update`/`secret_blank_or_masked?` já usados por `update`
   (`scout_tool.rb:70-78,137-139`) — não duplicar a lógica de merge, extraí-la para um método
   reutilizável entre os dois caminhos (ex. um novo `ScoutTool#auth_headers_for_execution(incoming)`
   ou reaproveitar `apply_credentials_update` sem persistir).
2. **A rota de teste precisa saber qual `ScoutTool` está sendo editado** para poder carregar o
   segredo salvo — mudar de `collection` para aceitar um `id` opcional (ferramenta ainda não salva
   continua testável sem merge, comportamento atual preservado nesse caso) ou o frontend passar o
   `id` no payload de teste quando `isEditing` (`ScoutToolModal.vue:52`) for verdadeiro.
3. Nenhuma mudança no mascaramento em si (`masked_auth_headers` permanece nunca devolvendo o segredo
   em claro) — o gap é exclusivamente no caminho de teste não reconciliar o mascarado de volta com o
   valor real antes de disparar a chamada HTTP.

## Escopo preliminar (a confirmar na especificação completa)

- `custom/app/controllers/api/v1/accounts/scout_tools_controller.rb`: `test` passa a resolver o
  `ScoutTool` existente (quando um identificador é enviado) e reconciliar `auth_headers`
  mascarado/vazio com o segredo salvo antes de montar o `HttpRequestExecutor`.
- `custom/app/models/scout_tool.rb`: extrair a lógica de merge de `apply_credentials_update` para um
  método reutilizável que não exija persistência (usado tanto por `update` quanto por `test`).
- `config/routes.rb` e/ou `ScoutToolModal.vue` (`handleTest`, `testPayload`): garantir que o teste de
  uma ferramenta já existente carregue o `id` para o backend localizar o segredo salvo.

## Fora de escopo desta fase (preview)

- Qualquer mudança no comportamento de mascaramento para `show`/`index`/`update` — permanecem como
  estão (nunca devolver segredo em claro).
- A causa raiz do 403 observado nas simulações da Fase 35 (credencial de teste "abobora" nunca
  substituída) — já resolvida diretamente pelo operador, atualizando `auth_headers` das 4
  `ScoutTool` da conta 1 no banco; não é um problema de código.
- Mudanças de código agora — este documento só registra o diagnóstico para tratamento futuro, a
  critério do operador.

## Testes (rascunho)

- `custom/spec/controllers/api/v1/accounts/scout_tools_controller_spec.rb` (ou onde o teste de
  action existir): novo `it` cobrindo que `POST .../scout_tools/test` para uma ferramenta existente,
  com `auth_headers` mascarado (`'••••••••'`) ou ausente, dispara o `HttpRequestExecutor` com o
  segredo real salvo — mock/expect no `HttpRequestExecutor.new`/`.execute` recebendo o valor
  decifrado, não a máscara. `it` de regressão cobrindo que uma ferramenta nova (sem id ainda salvo)
  continua exigindo o valor real digitado, sem regressão de segurança (nunca "vazar" segredo de
  outra ferramenta/conta).
- `custom/spec/models/scout_tool_spec.rb`: se a lógica de merge for extraída para um método novo,
  cobrir esse método isoladamente (mesmos casos já cobertos por `apply_credentials_update`, mas sem
  persistir).
- Verificação comportamental manual: editar uma `ScoutTool` existente com credencial válida salva,
  clicar "Testar" sem tocar no campo de credencial, confirmar sucesso (não mais 403/401 pela máscara).

## Critérios de aceite (rascunho, só valem se a fase avançar)

- Testar uma ferramenta externa já configurada, sem reditar o campo de credencial, usa o segredo
  real salvo e reflete o resultado real da API externa (sucesso ou falha real, nunca falha artificial
  por causa da máscara).
- `masked_auth_headers` continua nunca expondo o segredo em claro via `show`/`index`.
- Testar uma ferramenta nova (ainda não salva) continua exigindo a credencial real digitada no
  formulário — sem regressão do fluxo de criação.

---

> **Nota**: Preview criado ao investigar um relato do operador (conta 1 "Acme Inc", Scout "Vitória")
> sobre a Fase 35 — a causa raiz das simulações reportadas ali foi confirmada como credencial de
> teste ("abobora") nas 4 `ScoutTool` da conta, já corrigida diretamente no banco pelo operador. Este
> documento cobre um segundo problema, encontrado durante essa mesma validação: o botão "Testar" do
> editor de ferramentas envia sempre o valor mascarado (`'••••••••'`) para a API externa em vez do
> segredo real salvo, confirmado por leitura direta de código nos três pontos do caminho
> (`scout_tools_controller.rb#test`, `scout_tool.rb#masked_auth_headers`/`apply_credentials_update`,
> `ScoutToolModal.vue`), sem execução necessária contra uma API real — o fluxo de dados é
> determinístico. Tratamento completo adiado para o momento oportuno, a critério do operador — ver
> `spec60.md` §11. Próxima entrega via speckit, mesmo fluxo das fases 26, 23, 29, 32, 33 e 35.
