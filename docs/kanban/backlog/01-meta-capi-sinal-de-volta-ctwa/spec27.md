# Fase 27 — Sinal de volta para a Meta: eventos do kanban via API de Conversões, a partir do `ctwa_clid` (Brief)

**Status**: Preview
**Data**: 2026-10-20
**Depends on**: Fase 26 / spec 031 (`ciclo 7/08-whatsapp-referral-attribution/spec26.md`) — captura do `referral` e colunas `campaign_*` na oportunidade; Fase 40 (`ciclo 7/05-whatsapp-referral-evolution-patch/spec40.md`) — patch do Evolution que repassa o `referral` ao Chatwoot; Fase 46 (`ciclo 8/13-meta-referral-attribution-refinements/spec46.md`) — `CampaignAttributionSetting` (token Meta) e resolução de campanha.
**Substitui**: a versão anterior desta fase ("Facebook Campaign Data & Conversions API Integration", placeholder de set/2026). A parte 1 dela (resolver nomes de campanha, conjunto e anúncio pela Marketing API) já foi entregue nas Fases 26 e 46 (`Custom::CampaignResolutionJob`, `Meta::CampaignResolutionCache`). Sobra só a parte 2, o sinal de volta, que este brief detalha. Também absorve o item opcional "Disparo de Conversão Meta CAPI" do Scout (`ciclo 10/scoutv1/spec60.md` §2.4).

---

## 1. Problema *(mandatory)*

A Meta otimiza as campanhas de WhatsApp da Dens por **conversa iniciada**, que é a primeira mensagem do lead, muitas vezes só o texto pronto do anúncio. Não existe nenhum sinal de volta dizendo quem de fato conversou, agendou ou fechou.

Medição de 20/10/2026, cruzando o kanban (conta 2, `ichatr_opportunities` + `ichatr_opportunity_stage_changes`, de 08/08 a 20/10/2026) com o gasto do Gerenciador de Anúncios (conta 1247958619490898):

| Campanha | Gasto ago–out | Oportunidades | Conversou | Agendou | Ganho | R$ por agendamento |
|---|---|---|---|---|---|---|
| 14072026 [EST] (Estático 1/2, Mix Tv/higiene) | R$ 1.326 | 44 | 16 (36%) | 9 | 2 | R$ 147 |
| Engajamento – Backup | R$ 2.212 | 63 | 13 (21%) | 9 | 1 | R$ 246 |
| Leads – Lógica Condicional (3 versões) | R$ 2.883 | 56 | 15 (27%) | 9 | 3 | R$ 320 |
| Campanha Teste Bruna | R$ 427 | 35 | 4 (11%) | 1 | 0 | R$ 427 |
| **Todas** | **R$ 8.755** | **248** | **63 (25%)** | **37 (15%)** | **7** | **R$ 237** |

"Conversou" é o card que chegou a Em contato, Resgate, Agendado, No-show ou Em negociação. "Agendou" é o card que chegou a Agendado, No-show ou Em negociação.

- Só 1 em cada 4 leads de anúncio conversa, e 15% agendam.
- A campanha com a conversa mais barata (Teste Bruna, R$ 11,90 por conversa) foi a pior em agendamento. Otimizar por conversa iniciada premia exatamente o lead errado.
- O formulário de qualificação antes do WhatsApp (Lógica Condicional) encareceu a conversa e não melhorou a taxa de conversa.

## 2. Contexto técnico *(mandatory)*

### O `ctwa_clid` hoje, por caixa (mensagens com `referral` desde 01/08/2026, conta 2)

| Caixa | Número | Canal | Mensagens com `referral` | Com `ctwa_clid` |
|---|---|---|---|---|
| 3 "WhatsApp Business" | 41 3513-5000 (principal; recebe as campanhas) | `Channel::Api` via Evolution API | 224 | **0** |
| 15 "WhastApp Cloud" | 41 8432-7498 (notificações) | `Channel::Whatsapp` (Cloud API) | 46 | **40** |

Na caixa 3, o `referral` chega só com `body`, `headline`, `image_url`, `media_type`, `source_id`, `source_type` e `source_url`. Na caixa 15, chegam também `ctwa_clid`, `thumbnail_url`, `video_url` e `welcome_message`.

### Por que o `ctwa_clid` não chega pela caixa 3

- **O dado existe no protocolo.** `ExternalAdReplyInfo` tem `optional string ctwaClid = 13;` (Baileys 7.0.0-rc14, `WAProto/WAProto.proto:1368`), no mesmo struct de onde a Fase 40 já tira `sourceId` (8) e `sourceType` (7).
- **O patch da Fase 40 não extrai esse campo.** O `getAdsMessage` do fork `edneymatias/evolution-api` (`src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts`) passou a ler `sourceId`, `sourceType`, `mediaType` e `mediaUrl` (spec40, FR-001). O `ctwa_clid` ficou fora de escopo com a justificativa "not confirmed present in Baileys' `ExternalAdReplyInfo`". Ela estava errada: o campo existe (ver a nota de correção no spec40).
- **A Cloud API já manda o campo.** `Whatsapp::IncomingMessageServiceHelpers#referral_attributes` (`app/services/whatsapp/incoming_message_service_helpers.rb:93`) repassa o payload da Meta sem alterar, e por isso a caixa 15 tem o `ctwa_clid`. A premissa da Fase 26, de que nem a Cloud API mandava o campo, também ficou desatualizada.
- **O WhatsApp preenche o campo no número da ponte (confirmado em 20/10/2026).** No banco do Evolution (Metabase, database 7, tabela `"Message"`, coluna `"contextInfo"` → `externalAdReply`), a instância "Odontic Portão" (554135135000) tem 408 mensagens de anúncio desde 14/07/2026, e **376 delas (92%) trazem `ctwaClid`**. O formato é o mesmo da Cloud API (prefixo `Af…`, cerca de 138 caracteres). Desde 08/08/2026, quando o kanban começou, são 262 mensagens com o campo; 218 delas têm `chatwootInboxId = 3` e `chatwootConversationId`. Ou seja, **o dado já está gravado no Evolution e só não é repassado ao Chatwoot**.

### O que o Chatwoot faz com o `referral` hoje

- `Custom::ReferralAttributionService.extract_referral_data` (`custom/app/services/custom/referral_attribution_service.rb:19-32`) copia para a oportunidade `platform`, `source_id`, `source_url`, `headline`, `body`, `thumbnail_url` e `source_type`. **Não copia o `ctwa_clid`**, nem quando ele existe, como na caixa 15. Ele fica só no `content_attributes` da primeira mensagem, que se perde se o lead apagar a mensagem (spec26, "Architectural caveat: post-send deletion").
- `PipelineStage#campaign_report_milestone` (`custom/app/models/pipeline_stage.rb:17`) já marca uma única etapa como marco de campanha. Na conta 2, essa etapa é **Agendado** (`ichatr_pipeline_stages.id = 4`). É o candidato natural a gatilho do evento.

## 3. Precedente *(opcional)*

- **Upstream já conhece o campo.** `app/services/twilio/referral_params_helper.rb:12` mapeia `ReferralCtwaClid` para `ctwa_clid`, e `ReferralBubble.story.vue:13` usa o campo no exemplo.
- **Integração com a Meta.** `CampaignAttributionSetting` e `Custom::CampaignResolutionJob` (Fase 46) já resolvem token, erros OAuth e reprocessamento de pendentes. O envio de evento deve reutilizar o mesmo cliente e o mesmo padrão de job assíncrono com retry, em vez de criar um segundo.
- **O que não se aplica:** a resolução de campanha é só leitura (`ads_read`). Enviar evento exige escrita num conjunto de dados, provavelmente com outro escopo ou token (decisão 5).

## 4. Decisões *(mandatory)*

| # | Decisão | Justificativa |
|---|---|---|
| 0 | Antes do `/speckit-specify`, fazer uma investigação rápida que responda às decisões 1 e 5 | As duas podem inviabilizar a fase como desenhada. Construir antes de validar repete o erro da Fase 40, que descartou o campo sem verificar. A decisão 1 já foi respondida; falta a 5 |
| 1 | ~~Validar se o `ctwaClid` vem preenchido na caixa 3~~ **Respondida em 20/10/2026: sim** | 376 de 408 mensagens de anúncio da instância 554135135000 trazem o campo, no mesmo formato da Cloud API (seção 2). Falta só a decisão 5 |
| 2 | O patch do Evolution grava `ctwaClid` como `referral.ctwa_clid` | Mesmo nome de campo que a Cloud API usa. O Chatwoot trata as duas caixas igual, sem ramificar por provedor (objetivo da Fase 40) |
| 3 | Gravar o `ctwa_clid` na oportunidade (coluna nova `campaign_ctwa_clid` em `ichatr_opportunities`) no `ReferralAttributionService` | O evento sai dias depois, numa mudança de etapa. Depender da primeira mensagem é frágil (apagamento, seção 2). Mesmo padrão das demais colunas `campaign_*` |
| 4 | Gatilhos: entrada na etapa marco (`campaign_report_milestone`, hoje Agendado) envia o evento de agendamento; oportunidade ganha envia o evento de compra, com `value` | Usa marcadores que o kanban já tem, sem lista nova de etapas. Ganho com valor permite otimizar por valor no futuro. [A CONFIRMAR: nomes dos eventos (padrão `Schedule`/`Purchase` ou personalizados) e se "Em contato" também deve gerar evento, como sinal intermediário de "conversou"] |
| 5 | Destino: API de Conversões para mensagens de negócios (`action_source: business_messaging`, `messaging_channel: whatsapp`, `user_data.ctwa_clid`), no conjunto de dados que a Meta exigir | [A CONFIRMAR: (a) a Meta aceita evento com `ctwa_clid` de um número que não está na API oficial (app WhatsApp Business via Evolution)? (b) Qual conjunto de dados e qual token: o conjunto precisa estar ligado à conta do WhatsApp Business ou à Página? O pixel SITE (790154063087995) serve? Qual escopo o token precisa, além do `ads_read` da Fase 46?] |
| 6 | Envio assíncrono e sem bloqueio: job em background com retry, que registra falha e não impede a mudança de etapa | Resposta à questão já levantada na versão anterior desta fase: medição de anúncio não pode travar uma ação comercial |
| 7 | Idempotência: no máximo um evento por oportunidade e tipo de evento | Card que volta de No-show para Agendado não pode contar dois agendamentos para a Meta |
| 8 | Se a decisão 5(a) der "não": plano B é migrar o 3513-5000 para a Cloud API em coexistência (app + API) e manter o mesmo desenho a partir da decisão 3 | Mantém o número principal. A caixa 15 já prova que o `ctwa_clid` chega pela Cloud API. Custo: trocar a integração da caixa 3 (Evolution → Cloud API) |
| 9 | Preencher `campaign_ctwa_clid` das oportunidades existentes a partir do banco do Evolution (`"Message"."chatwootConversationId"` → conversa → oportunidade) e da caixa 15 (`content_attributes.referral.ctwa_clid`) | Recupera o histórico desde 08/08/2026 para relatório e testes. Enviar eventos retroativos à Meta depende da janela de tempo que ela aceita [A CONFIRMAR: até quantos dias depois do clique a Meta aceita o evento?]. Fora disso, o preenchimento serve só para medição |

## 5. Escopo preliminar *(mandatory)*

- Fork `edneymatias/evolution-api`, `chatwoot.service.ts` `getAdsMessage` e montagem do `referral`: adicionar `ctwaClid` → `referral.ctwa_clid` (mais o pipeline de imagem da Fase 42 para publicar).
- `db/migrate/…_add_campaign_ctwa_clid_to_ichatr_opportunities.rb`: coluna nova, aditiva (Constitution I).
- `custom/app/services/custom/referral_attribution_service.rb`: copiar `referral['ctwa_clid']` em `extract_referral_data` e nos dois `persist_*`.
- `custom/app/jobs/meta/…`: job novo de envio de evento (reutiliza o cliente e o token da Fase 46), disparado na mudança de etapa e no fechamento como ganho (ponto de gancho provável: `custom/app/listeners/custom/opportunity_activity_listener.rb`).
- `CampaignAttributionSetting` e tela de configurações: guardar o id do conjunto de dados (e o token, se for diferente).

## 6. Fora de escopo *(mandatory)*

- Conversões do chat do site (`gclid`/`fbclid`, consentimento de marketing): Fase 22 / `backlog/22-atribuicao-campanha-chat-do-site/spec91.md`, decisão 9. Pode reutilizar o job desta fase depois.
- Coleta diária de gasto por campanha: Fase 44 (`backlog/07-campaign-ad-spend-cost-tracking/spec44.md`).
- Evento disparado pelo Scout ao qualificar, sem passar pelo kanban (spec60 §2.4): o Scout move o card. Se mover para a etapa marco, o evento desta fase sai sozinho.
- Mudar a otimização das campanhas no Gerenciador para o evento novo: é configuração de anúncio, feita depois que os eventos estiverem chegando.
- Migração para a Cloud API: só entra se a decisão 8 for acionada.

## 7. Critérios de aceite (rascunho) *(mandatory)*

- Mensagem de anúncio que chega pela caixa 3 grava `content_attributes.referral.ctwa_clid` (quando o WhatsApp manda o campo), com o mesmo formato da caixa 15.
- Oportunidade criada de conversa com `referral.ctwa_clid` fica com `campaign_ctwa_clid` preenchido, nas duas caixas.
- Mover essa oportunidade para Agendado envia um único evento para a Meta. O evento aparece no Gerenciador de Eventos do conjunto de dados configurado, com o `ctwa_clid`.
- Marcar a oportunidade como ganha envia o evento de compra com o valor da proposta.
- Voltar a oportunidade para Agendado depois de No-show não envia um segundo evento.
- Falha no envio (token expirado, limite de requisições) não impede a mudança de etapa e fica registrada para retry.
- Oportunidade sem `ctwa_clid` (orgânica, site, indicação) não tenta enviar nada.

## 8. Testes (rascunho) *(opcional)*

- `custom/spec/services/custom/referral_attribution_service_spec.rb`: `ctwa_clid` copiado quando presente e ausente sem erro.
- `custom/spec/jobs/meta/…_spec.rb`: payload do evento (campos obrigatórios, `ctwa_clid`, `value` no ganho), idempotência e retry sem bloquear.
- Listener: entrada na etapa marco e no ganho enfileiram o job. Outras etapas não enfileiram.

## 9. Questões em aberto *(opcional)*

- **Evento intermediário de "conversou"?** A favor: dá volume de sinal muito maior (63 contra 37 no período) e é exatamente o comportamento que falta otimizar. Contra: "Em contato" depende de a recepção mover o card na hora certa, então o sinal é mais ruidoso que Agendado.
- **LGPD:** o spec91 (decisão 9) condiciona o envio de conversões do site ao aceite de marketing. Vale a mesma régua para o CTWA, em que o lead clicou num anúncio da própria Meta? [A CONFIRMAR com o advogado, junto da pergunta já aberta no spec91.]

---

## 10. Alterações feitas em outros documentos (20/10/2026, para revisar)

Estas notas foram adicionadas junto com esta versão da fase, para corrigir premissas erradas ou desatualizadas e apontar para cá:

| Documento | Onde | O que mudou |
|---|---|---|
| `ciclo 7/05-whatsapp-referral-evolution-patch/spec40.md` | Out of scope, item "`ctwa_clid` capture" | Nota de correção: o campo existe no Baileys (`ctwaClid = 13`) e a Cloud API manda o campo; a captura passou para esta fase |
| `ciclo 7/08-whatsapp-referral-attribution/spec26.md` | Lista "Observed real payload shape" | Nota de atualização: hoje a Cloud API também manda `ctwa_clid`, `thumbnail_url`, `video_url` e `welcome_message` |
| `ciclo 10/scoutv1/spec60.md` | §2.4 "Disparo de Conversão Meta CAPI (Opcional)" | Nota: o item foi absorvido por esta fase; o evento sai da mudança de etapa no kanban |
| `backlog/07-campaign-ad-spend-cost-tracking/spec44.md` | Linha `Depends on` | Caminho novo desta fase; a resolução de nomes de campanha passa a ser atribuída às Fases 26/46 |
| `backlog/22-atribuicao-campanha-chat-do-site/spec91.md` | Fora de escopo, item das conversões off-line (decisão 9) | Remete a esta fase: o envio do site deve reutilizar o mesmo job e o mesmo token |
| `backlog/01-facebook-campaign-integration/` | Pasta | Renomeada para `backlog/01-meta-capi-sinal-de-volta-ctwa/`; o `spec27.md` foi reescrito (este documento) |

---

> **Nota de proveniência**: a medição da seção 1 e a contagem de `ctwa_clid` por caixa vêm de consultas ao banco do Chatwoot (Metabase, database 2, conta 2) e do Gerenciador de Anúncios da conta 1247958619490898, em 20/10/2026. O campo `ctwaClid` foi confirmado no `WAProto.proto` do pacote `baileys@7.0.0-rc14`. Diagnóstico completo das campanhas: `claude-work/dens-meta-ads/diagnostico-meta-ads-out2026.md`. A presença do `ctwaClid` no Evolution foi confirmada no banco do Evolution (Metabase, database 7) em 20/10/2026. Próximo passo: investigação da decisão 5, depois `/speckit-specify`.
