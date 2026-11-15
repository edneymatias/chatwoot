# Fase 91 — Atribuição de campanha nas conversas do chat do site (Brief)

**Status**: `Preview`
**Data**: 2026-10-19
**Master doc**: site da Dens, `~/Projects/site-dens/docs/superpowers/specs/2026-10-19-chat-unico-design.md` (seções 4, 5 e 9 são o contrato com este brief)
**Depends on**: Fase 31 (`specs/031-whatsapp-referral-attribution`) e Fase 37 (`specs/037-meta-referral-attribution-refinements`): criaram a atribuição por `referral` do clique para WhatsApp (CTWA) que esta fase estende ao widget do site; Fase 44 (`specs/044-campaign-performance-report`): relatório que passa a receber os leads do site.

---

## 1. Problema *(mandatory)*

Leads que chegam pelo chat do site (caixa web da Dens, `inbox_id` 16, widget em `www.dens.com.br`) entram no kanban **sem campanha**: a oportunidade fica com `campaign_platform`, `campaign_source_id`, `campaign_name`, `campaign_adset_name` e `campaign_ad_name` vazios, então o relatório por campanha/conjunto/anúncio só enxerga o CTWA. O site da Dens passa a enviar, a partir do deploy do item C (ver Master doc), a origem de cada conversa nova como **atributos da conversa** (`origem`, `canal`, `pagina` sempre; `utm_*`, `gclid`, `fbclid`, `fbp`, `fbc`, `landing_page`, `referrer`, `primeira_visita` só com aceite de marketing). Sem esta fase, esses atributos ficam só no painel da conversa.

Dois achados de privacidade, confirmados com o advogado da Dens em 19/10/2026, também dependem do fork:
- o widget grava em `conversation.additional_attributes.referer` o **endereço completo** da página (`document.location.href`), com `gclid`/`utm` de quem veio de anúncio, **mesmo sem aceite de cookies**;
- a origem detalhada precisa de prazo de retenção (90 dias na conversa, igual ao navegador).

## 2. Contexto técnico *(mandatory)*

- `custom/app/services/custom/referral_attribution_service.rb:7-8`: a atribuição só existe com `content_attributes['referral']` na 1ª mensagem recebida (CTWA). Conversa do widget não tem `referral` → retorna sem gravar nada.
- `custom/app/services/custom/automation_rules/action_service.rb:22-34` (`persist_opportunity`) e `custom/app/services/custom/scout/tools/manage_opportunity.rb:158-163` (`process_referral_attribution`): os dois pontos que chamam a atribuição, ambos **no momento da criação** da oportunidade.
- **Os atributos do site chegam depois da criação da conversa.** O widget só aplica atributos pendentes quando cria a conversa (`app/controllers/api/v1/widget/base_controller.rb:43`; fila em `app/javascript/widget/store/modules/conversation/actions.js:215-222`), mas o pré-chat, ligado na caixa da Dens, cria a conversa **sem** a fila (`app/javascript/widget/views/PreChatForm.vue:64-71`, só `conversationCustomAttributes` do formulário). Conferido também na `upstream/develop` (mesmo comportamento). Por isso o site reenvia os atributos na 1ª mensagem, com `setConversationCustomAttributes`, um instante depois da criação.
- `app/controllers/api/v1/widget/conversations_controller.rb:67-68`: `set_custom_attributes` faz `conversation.update!(custom_attributes: …)`, **substituindo** todos os atributos. O site contorna gravando só em conversa recém-criada (Master doc, seção 5), mas qualquer chamada numa conversa antiga apaga o que a equipe preencheu.
- `app/controllers/api/v1/widget/base_controller.rb:41`: `referer: permitted_params[:message][:referer_url]`, que vem de `window.referrerURL` = `document.location.href` (SDK, `app/javascript/sdk/IFrameHelper.js`, observer de `onLocationChange`).
- **Todos os caminhos da URL da página no widget** (levantamento no código do fork, 20/10, a pedido do revisor externo). O SDK guarda `document.location.href` em `window.referrerURL` dentro do iframe (`app/javascript/sdk/DOMHelpers.js:42-68` → `IFrameHelper.js:252-255` → `app/javascript/widget/App.vue:287-295`, evento `change-url` a cada troca de página) e o reenvia em:
  1. **Criação da conversa** (`POST /widget/conversations` do pré-chat e `POST /widget/messages` sem conversa): `message[referer_url]` → `conversations.additional_attributes.referer` (`base_controller.rb:41`). **Grava no banco.**
  2. **Cada mensagem e anexo depois disso** (`endPoints.js:27-34` e `:50-61`): `message[referer_url]` chega ao servidor, mas `message_params` (`base_controller.rb:79-89`) não o usa. **Não grava no banco, mas aparece no log da requisição**: `config/initializers/filter_parameter_logging.rb` não filtra `referer_url`.
  3. **Eventos do widget** (`app/javascript/widget/api/events.js:4-9`, `generateEventParams`): `event_info.referer` em `POST /widget/events`. O `webwidget.triggered`, enviado **a cada abertura do chat** (`IFrameHelper.js:249`), é despachado por `events_controller.rb:4-7` sem gravar no banco, mas vai **inteiro** para os webhooks da conta inscritos em `webwidget_triggered` (`app/listeners/webhook_listener.rb:45-51`) e para os agent bots da caixa (`app/listeners/agent_bot_listener.rb:54-60`). Na conta 2 **não há** webhook inscrito nesse evento nem agent bot na caixa 16 (Matias, 20/10): hoje o caminho não vaza, mas a limpeza o cobre para quando houver.
  4. **Campanha do widget** (`campaign.triggered`, `endPoints.js:102-115`): `CampaignListener` (`app/listeners/campaign_listener.rb:12`) passa o `event_info`, com o `referer`, para `CampaignConversationBuilder`, que grava em `conversations.additional_attributes`. **Não há** campanha de site ativa na caixa 16 (Matias, 20/10): hoje não vaza; a limpeza cobre o futuro.
  5. **Contato:** nada no widget grava a URL da página no contato (`widgets_controller.rb` e `configs_controller.rb` só gravam `created_at_ip`, e só com `ip_lookup`, desligado na conta). A suspeita do revisor não se confirma na 4.18.
  6. **Fora do servidor do Chatwoot:** o `currentURL` das campanhas é usado só no navegador para escolher a campanha (`store/modules/campaign.js`), não é enviado. O cabeçalho `Referer` das requisições do navegador ao `app.ichatr.com.br` leva só a origem (`https://www.dens.com.br/`): o site não define `Referrer-Policy`, e o padrão dos navegadores (`strict-origin-when-cross-origin`) corta caminho e parâmetros entre domínios (conferido por `curl -I` em 20/10).
- `app/controllers/widgets_controller.rb:11` (`before_action :build_contact`): todo carregamento do widget sem token cria um contato anônimo; com o recurso `ip_lookup` da conta, grava `created_at_ip` (linhas 66-72). Relevante para a política de privacidade da Dens.
- `app/javascript/sdk/IFrameHelper.js:155-156`: `cw_conversation` é gravado a cada carregamento do widget, haja conversa ou não.
- `custom/app/jobs/custom/campaign_resolution_job.rb:48-49`: resolve nomes pela Graph API a partir de `opportunity.campaign_source_id` (ID do anúncio da Meta). Os anúncios da Meta que levam ao site vão mandar `utm_content={{ad.id}}`, então o mesmo job serve.
- `app/javascript/dashboard/composables/useOpportunityCardFields.js:176-180`: ícone do card só conhece Instagram e Facebook. `app/javascript/dashboard/components-next/filter/opportunityProvider.js:110-115`: filtro por `campaign_platform`.

## 3. Precedente *(opcional)*

A atribuição do CTWA (Fases 31/37) é o modelo: mesmas colunas `campaign_*`, mesmo `campaign_resolution_status`, mesmo job de resolução pela Graph API e mesmo relatório (Fase 44). O que muda é a **fonte**: no CTWA, `message.content_attributes['referral']` (entregue pela Meta); no site, `conversation.custom_attributes` (entregue pelo SDK). O site não tem como escrever no mesmo lugar do CTWA: a API de mensagens do widget só aceita `content`, `referer_url`, `timestamp`, `echo_id` e `reply_to` (`app/controllers/api/v1/widget/messages_controller.rb:89`). Não se aplica do CTWA: a classificação orgânico × pago por `source_type`/`story_fbid`; no site quem diz isso é o `canal` (lista fechada, calculada pelo site).

## 4. Decisões *(mandatory)*

| # | Decisão | Justificativa |
|---|---|---|
| 1 | O pré-chat envia a fila de atributos pendentes junto com os do formulário (`PreChatForm.vue`: merge de `getPendingCustomAttributes` em `customAttributes`, e limpa a fila depois) | É o único caminho para a conversa nascer com a origem, antes de qualquer automação rodar. Correção candidata a PR no upstream (o bug existe na `develop`) |
| 2 | `set_custom_attributes` do widget faz `merge` (`conversation.custom_attributes.merge(…)`) | Gravar origem não pode apagar atributos preenchidos pela equipe ou pelo Scout. Comportamento também candidato a upstream |
| 3 | `additional_attributes.referer` é gravado **sempre** sem parâmetros de campanha (`gclid`, `gbraid`, `wbraid`, `gad_source`, `gad_campaignid`, `fbclid`, `utm_*`, `ad_id`, `ttclid`, `msclkid`) | O fork não sabe do consentimento do site; com aceite, os mesmos dados chegam pelos atributos, então nada se perde. Decisão do advogado (19/10): sem aceite, esses dados não podem ir. Auditoria de 20/10 (Metabase): o campo já tem `gclid`, `gbraid`, `gad_campaignid` e `utm_source=chatgpt.com` em conversas reais da caixa 16 (ex.: conversa 73889, 19/10). Por isso o `referer` **não** deve servir de reserva para `gclid`/UTM na atribuição; [A CONFIRMAR com o advogado: o que fazer com os `referer` já gravados] |
| 3a | A limpeza da decisão 3 vale para **todos os caminhos** por onde o widget manda a URL da página (levantamento no código, 20/10, abaixo), num ponto só no servidor: um `before_action` em `Api::V1::Widget::BaseController` que limpa `params[:message][:referer_url]` e `params[:event_info][:referer]` antes de qualquer uso; mais `referer_url` e `referer` em `filter_parameters` para os logs | Limpar só `conversations.additional_attributes` deixaria a URL completa sair por webhook, por campanha do widget e pelos logs. No servidor, cobre também widgets antigos em cache no navegador |
| 4 | Atribuição web: sem `referral`, ler `conversation.custom_attributes` (chaves do contrato abaixo) e preencher `campaign_*` | Converge site e CTWA nas mesmas colunas e no mesmo relatório. **O lugar de convergência e de visualização é o painel de oportunidades** (Matias, 19/10): as chaves do contrato **não** têm definição de atributo personalizado na conta, então não aparecem no painel lateral da conversa (`CustomAttributes.vue:76-89` só lista atributos definidos) e a atribuição deve lê-las direto do JSON, sem depender de `CustomAttributeDefinition` |
| 5 | A atribuição web roda também quando os atributos da conversa mudam (evento de atualização da conversa) e a oportunidade de origem ainda está sem `campaign_platform` | Com a decisão 1 os atributos chegam na criação; sem ela (ou com pré-chat desligado em outra caixa) chegam logo depois. Idempotente: não sobrescreve atribuição já feita |
| 6 | Meta → site: `campaign_source_id = utm_content` (o site manda `{{ad.id}}`), status `pending` e o mesmo `CampaignResolutionJob` | Mesmo caminho do CTWA; dá campanha, conjunto, anúncio e miniatura |
| 7 | Exclusão automática da camada de detalhe (`utm_*`, `gclid`, `fbclid`, `fbp`, `fbc`, `landing_page`, `referrer`, `primeira_visita`) da conversa 90 dias depois da criação; `origem`, `canal` e `pagina` ficam | Mesmo prazo dos cookies de origem no navegador (decisão do Matias, 19/10). A política da Dens só cita o prazo quando esta exclusão existir |
| 8 | Retenção desses dados **na oportunidade** | [A CONFIRMAR: revisitar na implementação (Matias, 19/10). A LGPD não fixa prazo, mas exige guardar só o necessário (art. 6º, III) e encerrar quando a finalidade acaba (arts. 15 e 16); opções: igualar aos 90 dias, guardar até a oportunidade fechar + N meses, ou manter só os nomes de campanha e apagar `gclid`/`fbclid`] |
| 9 | Conversões off-line (enviar ao Google Ads/Meta as oportunidades ganhas com `gclid`/`fbclid` e valor) só para conversas com aceite de marketing, ou seja, só quando a conversa tiver os atributos de detalhe | Decisão do advogado (19/10). Fica **fora desta fase** (seção 6); registrado aqui porque depende destes atributos |

### Contrato com o site (atributos da conversa)

Valores texto, até 500 caracteres; chave sem valor não é enviada.

| Chave | Camada | Valores |
|---|---|---|
| `origem` | sempre | `card_<slug>` (slug estável da tabela `service` do NocoDB do site, ex.: `card_protocolo`; não muda quando o tratamento é renomeado), `barra_fixa`, `contato`, `jornada`, `form_erro`, `bolha` |
| `canal` | sempre | tipo de origem **da sessão atual** (último toque), com o mesmo significado com e sem aceite: `google_ads`, `meta_ads`, `perfil_google`, `busca_google`, `ia` (ChatGPT, Perplexity, Copilot, Gemini, Claude), `instagram`, `facebook`, `whatsapp`, `outro_site`, `campanha_outra`, `direto` |
| `pagina` | sempre | caminho sem parâmetros (`/`) |
| `ia_servico` | sempre, só com `canal=ia` | `chatgpt`, `perplexity`, `copilot`, `gemini`, `claude`. Mapa sugerido → `campaign_platform` da oportunidade (o mesmo valor), para filtrar no painel como hoje se filtra `instagram`/`facebook` |
| `utm_source`, `utm_medium`, `utm_campaign`, `utm_term`, `utm_content`, `gclid`, `gbraid`, `wbraid`, `gad_source`, `gad_campaignid`, `fbclid`, `fbp`, `fbc`, `landing_page`, `referrer`, `primeira_visita`, `canal_primeira_visita`, `ia_servico_primeira_visita` | só com aceite de marketing | do **primeiro acesso em 90 dias** (primeiro toque); `primeira_visita` em `AAAA-MM-DD`; `canal_primeira_visita` e `ia_servico_primeira_visita` com os mesmos valores de `canal` e `ia_servico`. `gbraid`/`wbraid` substituem o `gclid` em parte dos cliques do Google Ads no iPhone. `gad_campaignid` é o ID da campanha do Google Ads, posto pelo próprio Google em todo clique de anúncio |

Convenção de UTMs que o Matias vai configurar:
- **Google Ads** (sufixo do URL final): `utm_source=google&utm_medium=cpc&utm_campaign={campaignid}&utm_content={adgroupid}_{creative}&utm_term={keyword}` (o Google só tem macros de ID).
- **Meta → site** (parâmetros de URL do anúncio): `utm_source={{site_source_name}}&utm_medium=paid&utm_campaign={{campaign.name}}&utm_content={{ad.id}}&utm_term={{adset.name}}`.

Mapa proposto → oportunidade. Com a camada de detalhe, a oportunidade usa o **primeiro toque** (`canal_primeira_visita` e detalhes), como o CTWA, em que o anúncio é o que trouxe a pessoa; sem ela, usa o `canal` da sessão, sem identificar campanha. [A CONFIRMAR na implementação: guardar também o `canal` da sessão na oportunidade (último toque), para comparar os dois no relatório.] `google_ads` vale para `gclid`, `gbraid` ou `wbraid`.

| `canal` | `campaign_platform` | `campaign_source_id` | Nomes | `campaign_resolution_status` |
|---|---|---|---|---|
| `meta_ads` | `facebook` (`utm_source` `fb`/`facebook`) ou `instagram` (`ig`/`instagram`) | `utm_content` (ID do anúncio) | Graph API (job existente) | `pending` → `resolved` |
| `google_ads` | `google` | `gad_campaignid` (ID da campanha; na falta, `utm_campaign`) | [A CONFIRMAR: questão 9.1] | [A CONFIRMAR: novo status ou `not_applicable`] |
| `perfil_google`, `busca_google`, `ia`, `instagram`, `facebook`, `whatsapp`, `outro_site`, `campanha_outra`, `direto` | [A CONFIRMAR: valores orgânicos; ex. `google_business_profile`, `google_search`, `ai_assistant`, `instagram`, `facebook`, `whatsapp`, `web`, `web`, `direct`] | — | `utm_campaign` quando houver | [A CONFIRMAR: `organic_post` hoje significa “post orgânico da Meta”; criar `organic`?] |

**Auditoria da conta 2 (20/10, via Metabase, feita por revisor externo):**
- 12 regras de automação (8 ativas), nenhuma grava atributo de conversa; a origem hoje só vira rótulo (`site`, `facebook`, `insite`). A decisão 2 (`merge`) não é pré-requisito do site.
- **Nenhuma regra cria oportunidade para a caixa 16 (chat do site).** A regra 9 (“Rotulagem de campanha externa – Google”) procura “Olá! Estou no site da Odontic Portão”, texto do antigo link de WhatsApp do site, que não existe mais. A regra 17 depende de `campaign_referral_present` (CTWA). Sem uma regra para a caixa 16, a atribuição web desta fase não tem oportunidade onde gravar. A regra nova é configuração do Matias (instrução no plano do site), independente desta fase.
- O modelo de oportunidade tem `origem_da_oprotunidade` (grafia do banco), lista Facebook/Instagram, Google, Site, Fachada, Indicação, Orgânico, Interno, preenchida por IA ou à mão. [A CONFIRMAR na implementação: pré-preencher a partir de `canal`/`canal_primeira_visita` quando estiver vazia (ex.: `google_ads` → Google; `meta_ads`, `instagram`, `facebook` → Facebook/Instagram; demais do site → Site), sem sobrescrever o que a equipe ou a IA escolheram; e se vale corrigir a grafia da chave, que tem dados gravados.]
- Chaves soltas `origem` e `campanha` em uma conversa cada, de 2025 (legado). `origem` é reaproveitada de propósito pelo site; a atribuição web só deve tratar conversas da caixa do site que tenham `canal`.

## 5. Escopo preliminar *(mandatory)*

- `app/javascript/widget/views/PreChatForm.vue` (+ spec): fila de atributos no pré-chat (decisão 1).
- `app/controllers/api/v1/widget/conversations_controller.rb` (+ request spec): `merge` em `set_custom_attributes` (decisão 2). Avaliar se vai como patch em `custom/` ou PR upstream (Constituição: arquivos core).
- `app/controllers/api/v1/widget/base_controller.rb`: `before_action` de limpeza (decisões 3 e 3a) para `params[:message][:referer_url]` e `params[:event_info][:referer]`; helper de limpeza em `custom/`. `config/initializers/filter_parameter_logging.rb`: `referer_url` e `referer`.
- `custom/app/services/custom/referral_attribution_service.rb` ou serviço irmão `Custom::WebAttributionService`: atribuição web (decisões 4 e 6) e chamada a partir de `action_service.rb:33-34` e `manage_opportunity.rb:158-163`.
- Listener de atualização de conversa (padrão de `custom/app/listeners/custom/`): decisão 5.
- Job agendado de retenção (decisão 7).
- `useOpportunityCardFields.js`, `opportunityProvider.js`, i18n: ícone e filtro para `google` e os canais orgânicos.
- `custom/app/services/reports/campaign_performance_builder.rb`: conferir se os novos `campaign_platform` entram sem ajuste.

## 6. Fora de escopo *(mandatory)*

- Conversões off-line para Google Ads e Meta (decisão 9): fase própria. Pré-requisitos já sabidos: só com aceite de marketing; [A CONFIRMAR com o advogado: base legal para enviar à Meta, como conversão off-line, os leads do CTWA, que não passam por banner de cookies]. O envio de eventos de WhatsApp (CTWA) para a Meta a partir do kanban é a Fase 27 (`docs/kanban/backlog/01-meta-capi-sinal-de-volta-ctwa/spec27.md`); o envio do site deve reutilizar o mesmo job e o mesmo token quando for feito.
- `setUser` no widget (repasse de nome e celular do formulário do site): decisão do site, fica para depois.
- Resolver nomes do Google Ads pela API (questão 9.1), se a decisão for UTM manual.
- Qualquer mudança no site da Dens (já especificada no Master doc).

## 7. Critérios de aceite (rascunho) *(mandatory)*

- Conversa nova pelo widget com pré-chat e atributos pendentes nasce com esses atributos (sem depender de uma 2ª chamada).
- `setConversationCustomAttributes({ origem: 'x' })` numa conversa com `assunto` preenchido mantém `assunto`.
- `additional_attributes.referer` de uma conversa iniciada em `https://www.dens.com.br/?gclid=abc&utm_source=google` é `https://www.dens.com.br/`, tanto pelo pré-chat (`POST /widget/conversations`) quanto pela 1ª mensagem sem pré-chat (`POST /widget/messages`).
- O payload de `webwidget_triggered` entregue a webhooks e agent bots traz `event_info.referer` sem parâmetros de campanha.
- Conversa criada por campanha do widget (`campaign.triggered`) tem `additional_attributes.referer` sem parâmetros de campanha.
- O log da requisição não mostra `referer_url`/`referer` com `gclid`.
- Oportunidade criada de conversa do site com `canal=meta_ads` e `utm_content=<ad id>` chega a `resolved` com campanha, conjunto e anúncio, como no CTWA.
- Oportunidade de conversa com `canal=google_ads` aparece no relatório por campanha com `campaign_platform=google`.
- Atributos que chegam depois da criação da oportunidade preenchem `campaign_*` vazios e nunca sobrescrevem atribuição existente.
- 90 dias depois, a conversa não tem mais os atributos de detalhe; `origem`, `canal` e `pagina` continuam.

## 8. Testes (rascunho) *(opcional)*

- `spec/javascript` do `PreChatForm`: pendentes + formulário vão juntos; fila limpa.
- `spec/requests/api/v1/widget/conversations_request_spec.rb`: `set_custom_attributes` com merge.
- Request specs do widget: `referer` sem parâmetros de campanha em `conversations#create`, `messages#create` (com e sem conversa), `events#create` (payload despachado) e na conversa criada por `campaign.triggered`.
- `custom/spec/services/custom/...`: mapa `canal` → `campaign_*`, precedência sobre `referral` (CTWA vence quando houver `referral`), idempotência.
- `custom/spec/jobs/...`: retenção apaga só a camada de detalhe.

## 9. Questões em aberto *(opcional)*

**9.1 Nomes das campanhas do Google Ads.** UTM manual por campanha (`utm_campaign=<nome>` escrito à mão no Google Ads) ou job novo na Google Ads API (resolve `campaignid`/`adgroupid`/`creative` como o job da Meta)? A favor do manual: zero código, poucas campanhas (Pesquisa, raio de 6 km). Contra: depende de disciplina a cada campanha nova e não traz o nome do grupo nem do anúncio. A favor da API: simetria com a Meta. Contra: token de desenvolvedor e OAuth, desproporcional para uma conta só [INFERÊNCIA: burocracia de acesso não conferida].

**9.2 `merge` e fila: patch no fork ou PR upstream primeiro?** Os dois bugs (decisões 1 e 2) existem na `develop`. A favor do PR: menos patch core para manter no sync (Fase 21). Contra: prazo do upstream; a Dens precisa antes.

---

> **Nota de proveniência**: levantado na sessão de design do item C do site da Dens (19/10/2026), por leitura do código do fork (4.18.0-ichatr) e da `upstream/develop`, da configuração pública do widget da Dens (`/widget?website_token=…`: pré-chat com nome e celular, atributos de conversa `tipo_atendimento`, `assunto`, `desfecho`) e do SDK servido em `app.ichatr.com.br`. Decisões de consentimento e retenção: Matias com o advogado, 19/10. Implementação sem data. Próximo passo: brainstorm/speckit quando o Matias priorizar (`/speckit-specify`).
