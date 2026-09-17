# Fase 01 — Fundação do Framework de Integração ERP e Configuração do Younus

**Depende de**: nenhuma dependência de código prévia — feature nova, sem precedente direto de "ERP →
Chatwoot" no fork (a direção contrária, CRM outbound, existe no LeadSquared:
`app/services/crm/leadsquared/`).
**Sucede/Precede**: Fase 02 (`02-erp-contact-panel-data-card/spec95.md`) depende do hook configurado
e habilitado aqui.

---

## Objetivo

Hoje o Chatwoot só oferece integração de saída com sistemas de CRM/ERP (LeadSquared: Chatwoot → CRM,
`app/services/crm/`). Não existe nenhum caminho para trazer dados de um ERP externo *para dentro* do
Chatwoot. Esta fase estabelece a fundação plugável (contrato de adapter, feature flag, tela de
configuração) e implementa o primeiro provedor real, o ERP Younus, com autenticação por token e
validação síncrona de conexão. A exibição dos dados no painel do contato é escopo da Fase 02.

## Contexto de investigação (por que este desenho)

- **Precedente direto de integração pluggable multi-provider já existe**, só que na direção oposta:
  `Integrations::Hook` (`app/models/integrations/hook.rb`) é o modelo genérico (account/inbox,
  `settings` jsonb, `access_token`, `status`) reaproveitado por Slack, Notion, Shopify, LeadSquared
  etc. Cada provedor é uma entrada em `config/integration/apps.yml` (`settings_json_schema`/
  `settings_form_schema` dirigem um formulário `FormKit` genérico em `NewHook.vue`) e uma feature
  flag por conta em `config/features.yml` (ex.: `crm_integration`, ligada no Super Admin). O CRM
  LeadSquared (`Crm::SetupJob`, `Crm::Leadsquared::*`) já tem o comentário
  `# Add cases for future CRMs here` — foi desenhado esperando mais de um provedor.
- **Validação síncrona de credencial ao salvar já existe**: `Integrations::Hook#validate_openai_api_key`
  chama `Integrations::Openai::KeyValidator.valid?(api_key)` (`lib/integrations/openai/key_validator.rb`)
  como uma `validate` comum — se a chave for inválida (API responde 401), o `save` falha e o erro
  aparece no formulário. Vamos espelhar exatamente esse padrão para o Younus, sem precisar de
  endpoint dedicado de "testar conexão" nem job assíncrono.
- **Não existe hoje nenhuma tela de "grupo de integrações → escolher provedor"** — cada app é um card
  solto na grade de Integrações. Como este framework precisa suportar múltiplos ERPs no futuro (o
  operador confirmou: desativar Younus, ativar outro provedor, sem tocar em UI/backend genérico),
  introduzimos um novo campo `category` em `apps.yml` e uma tela nova de seleção, exercida pela
  primeira vez aqui.
- **API do Younus** (fornecida pelo operador, sem documentação pública): autenticação por header
  estático `token`; endpoint de busca de pessoa por telefone
  `GET https://wfh.ichatr.com.br/webhook/pessoas?idEmpresa=<id>&nrTelcelpessoa=<telefone>`. Respostas:
  `401`/`403` = token inválido; `503` = erro de parâmetro/serviço; `200` sempre, com `sucesso:
  true|false` no corpo indicando se achou a pessoa.

## Decisões de desenho

1. **Reaproveitar `Integrations::Hook` como modelo de persistência** — nenhuma tabela nova. Cada
   provedor ERP é só mais um `app_id` (`younus` agora), com `hook_type: account`,
   `allow_multiple_hooks: false`, igual ao LeadSquared.
2. **Contrato mínimo, sem abstração de "esquema de autenticação" genérico** (YAGNI) — cada adapter
   (`Erp::Younus::Adapter < Erp::BaseAdapter`) monta seu próprio cliente HTTP do jeito que a API dele
   exigir. O contrato só define os métodos que o *core* do Chatwoot precisa chamar: `test_connection`,
   e (Fase 02) `find_by_id`/`search_by_phone`/`phone_from`.
3. **Validação de conexão é síncrona, na gravação do Hook** (`ActiveRecord validate`), não um
   botão/endpoint separado — mesmo padrão do `validate_openai_api_key`.
4. **Sem trava de exclusividade entre app_ids ERP diferentes no banco** — se o operador habilitar dois
   provedores ERP ao mesmo tempo, ambos os cards apareceriam (Fase 02); o fluxo esperado (declarado
   pelo operador) é desabilitar um antes de habilitar outro, não uma restrição de dados.
5. **Direção da sincronização, v1: somente leitura, ERP → Chatwoot.** O contrato (`Erp::BaseAdapter`)
   hoje só declara métodos de leitura. Isso é uma limitação da v1, não uma decisão arquitetural
   permanente — nada no desenho impede adicionar métodos de escrita (`push_contact`, etc.) a um
   adapter no futuro; seria estritamente aditivo, sem quebrar o contrato existente nem a tela de
   configuração.
6. **Tela de seleção de provedor é uma camada nova no frontend, não uma mudança no backend genérico de
   apps** — `apps.yml` ganha um campo `category: erp` por entrada; a grade de Integrações agrupa todo
   app com essa categoria em um único card "ERP"; o clique leva a uma lista de provedores (só Younus
   agora); o clique no provedor reaproveita 100% a rota/formulário genérico já existente
   (`IntegrationHooks.vue` → `NewHook.vue`).

## Escopo — User Stories

### US1 — Super Admin habilita a integração ERP para uma conta

Como Super Admin, eu habilito a feature `erp_integration` para uma conta específica, para que a opção
de integração ERP passe a aparecer nas configurações dessa conta.

- Nova entrada em `config/features.yml`: `name: erp_integration`, `display_name: ERP Integration`,
  `enabled: false` (opt-in por conta, igual `crm_integration`).
- Sem a flag habilitada, o card "ERP" não aparece na grade de Integrações (`Integrations::App#enabled?`
  retorna `false` — novo `when` no `case` analogamente a `crm_integration`).

**Critérios de aceite**:
- Conta sem a flag: nenhum card "ERP" nem rota `/settings/integrations/erp` acessível (redireciona/
  oculta como qualquer feature-gated route hoje).
- Conta com a flag: card "ERP" visível na grade de Integrações.

### US2 — Admin escolhe o provedor ERP e configura as credenciais do Younus

Como Admin da conta, eu clico no card "ERP", vejo a lista de provedores suportados (só Younus, por
ora), escolho um, informo o token de API e o ID da empresa no Younus, e ao salvar o sistema testa a
conexão automaticamente.

- `config/integration/apps.yml`, nova entrada `younus`: `id: younus`, `feature_flag: erp_integration`,
  `category: erp`, `hook_type: account`, `allow_multiple_hooks: false`, `settings_json_schema` com
  `token` (string, obrigatório) e `id_empresa` (string, obrigatório), `settings_form_schema` com os
  dois campos de texto.
- Nova página `Erp/Index.vue` (rota `settings_integrations_erp`, `/settings/integrations/erp`): lista
  os apps com `category: erp` (só Younus) como opções clicáveis; clicar leva à rota genérica existente
  `:integration_id` (`IntegrationHooks.vue`/`SingleIntegrationHooks.vue`/`NewHook.vue`) — reaproveita o
  `FormKit` dinâmico, nenhum formulário novo.
- `Integrations/Index.vue`: apps com `category: erp` deixam de aparecer como cards soltos na grade
  principal e passam a ser representados por um único card agrupado "ERP" que leva à página acima.
- `Integrations::Hook#erp_integration?` (`%w[younus].include?(app_id)`, mesmo padrão de
  `crm_integration?`).
- `Integrations::Hook#validate_erp_credentials` (nova `validate`, condicionada por
  `validate_erp_credentials?`, mesmo padrão de `validate_openai_api_key?`): resolve o adapter via
  `Erp::AdapterFactory.build(self)` e chama `test_connection`; se levantar `Erp::AuthenticationError`,
  adiciona erro "Credenciais inválidas"; se `Erp::ApiError`, adiciona erro "Não foi possível conectar
  ao ERP".
- `Erp::Younus::Client` (HTTParty): `base_uri 'https://wfh.ichatr.com.br'`;
  `GET /webhook/pessoas?idEmpresa=<id_empresa>&nrTelcelpessoa=<telefone>`, header `token`. Mapeamento:
  `401`/`403` → `Erp::AuthenticationError`; `503` → `Erp::ApiError`; `200` com `sucesso: false` no
  corpo → retorno "não encontrado" (não é erro); `200` com `sucesso: true` → retorna o hash de
  `dados[0]['json']`.
- `Erp::Younus::Adapter#test_connection`: chama `client.search_by_phone` com um telefone claramente
  inválido (ex.: `"0"`), espera "não encontrado" como sucesso (confirma que o token autenticou); só
  falha (`false`) se `Erp::AuthenticationError` for levantada.

**Critérios de aceite**:
- Token e ID da empresa em branco: formulário bloqueia o envio (schema `required`), sem chamar a API.
- Token inválido: ao salvar, a API responde 401/403, o save falha, erro "Credenciais inválidas"
  aparece no formulário, hook não é persistido/habilitado.
- Token válido: ao salvar, a API responde 200 (achado ou não achado), o hook é salvo como `enabled`, o
  card do Younus aparece marcado como conectado na tela de provedores.
- Erro 503 (parâmetro malformado, serviço fora do ar): save falha com mensagem "Não foi possível
  conectar ao ERP", distinta da mensagem de credenciais inválidas.

### US3 — Desenvolvedor plugável: adicionar um novo provedor ERP não exige mudar UI, endpoint ou card

Como Desenvolvedor, quando eu adicionar um segundo provedor ERP (ex.: Simples Dental) no futuro, minha
única mudança é: uma entrada em `apps.yml` (`category: erp`) + uma classe
`Erp::SimplesDental::Adapter < Erp::BaseAdapter` implementando os métodos do contrato + uma linha no
`Erp::AdapterFactory`. Nenhum código da tela de seleção, do formulário genérico, do endpoint de dados
(Fase 02) ou do card no painel do contato muda.

- `Erp::BaseAdapter` (`app/services/erp/base_adapter.rb`): classe abstrata definindo os métodos que
  todo provedor deve implementar (`self.erp_name`, `test_connection`; `find_by_id`/`search_by_phone`/
  `phone_from` chegam na Fase 02) e levantando `NotImplementedError` nos métodos não implementados.
- `Erp::AdapterFactory` (`app/services/erp/adapter_factory.rb`):
  `case hook.app_id; when 'younus' then Erp::Younus::Adapter.new(hook) end` — mesmo idioma de
  `Crm::SetupJob#setup_service`.
- `Erp::AuthenticationError` / `Erp::ApiError` (`app/services/erp/errors.rb`): hierarquia de erro
  compartilhada entre provedores, mesmo papel de `Crm::Leadsquared::Api::BaseClient::ApiError`.

**Critérios de aceite**:
- `Erp::AdapterFactory.build` para um `app_id` desconhecido levanta um erro explícito (não retorna
  `nil` silenciosamente).
- Chamar qualquer método do contrato numa subclasse que não o implementa levanta `NotImplementedError`
  com o nome do método — falha alto e cedo, não silenciosa.

## Fora de escopo

- Exibição dos dados do ERP em qualquer tela (card no painel do contato, cache de ID por contato,
  empty state) — Fase 02.
- Qualquer escrita no ERP (Chatwoot → Younus) — não faz parte do contrato desta versão; decisão
  explícita do operador de manter aberto para o futuro, sem nenhuma modelagem antecipada.
- Uso do Younus como `ScoutTool` (`call_custom_api`) para lógica de handoff do Scout — mecanismo
  independente, já coberto por `23-non-sales-intent-immediate-handoff/spec86.md` (decisão explícita de
  manter a consulta ao ERP como reforço opcional configurado pelo operador via UI de Ferramentas, não
  uma integração de código); esta fase não tem nenhuma relação com aquele mecanismo.
- Botão dedicado de "testar conexão" antes de salvar — o teste acontece no `save`, mesmo padrão do
  OpenAI.
- Trava de exclusividade entre múltiplos hooks ERP habilitados simultaneamente.

## Testes

- Model spec (`spec/models/integrations/hook_spec.rb`): `validate_erp_credentials` cobrindo token
  válido (save sucede), 401/403 (save falha, mensagem de credenciais), 503 (save falha, mensagem de
  conexão), schema inválido (campos obrigatórios ausentes).
- Spec do `Erp::Younus::Client` com `WebMock`, cobrindo os formatos de resposta reais fornecidos pelo
  operador (sucesso, não encontrado, 401/403, 503).
- Spec do `Erp::AdapterFactory` (app_id conhecido resolve a classe certa; desconhecido levanta erro).
- Component spec da `Erp/Index.vue` (lista o Younus, navega para o formulário) e do agrupamento em
  `Integrations/Index.vue` (apps `category: erp` viram um card único).

## Critérios de aceite (fase)

- Com a flag `erp_integration` desligada, nenhuma UI nova é visível.
- Com a flag ligada, o fluxo completo funciona: Integrações → card "ERP" → lista de provedores →
  Younus → formulário → salvar com token+id_empresa válidos → hook habilitado.
- Token/ID inválidos nunca resultam em hook habilitado silenciosamente — sempre erro visível no
  formulário.
- Nenhuma mudança de comportamento em integrações existentes (Slack, Notion, Shopify, LeadSquared).
