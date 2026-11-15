# Fase 96 — Público de campanha por lista de contatos (Brief)

**Status**: `Preview`
**Data**: 2026-10-23
**Depends on**: Fase 72 (`docs/kanban/backlog/13-whatsapp-campaign-reply-tracking/spec72.md`, `specs/045-whatsapp-campaign-reply-tracking`): criou `Custom::Whatsapp::OneoffCampaignService` e `ichatr_campaign_recipients`, que esta fase estende.

---

## 1. Problema *(mandatory)*

Na criação de campanhas de WhatsApp (e de SMS), o público só pode ser definido por **etiquetas**. O módulo de contatos já permite filtrar contatos por atributos (nome, telefone, país, atributos personalizados, etiquetas, datas) e salvar o filtro como **lista** (na UI, "segmento"). Esse filtro não pode ser usado como público de campanha: para disparar para um recorte, a equipe precisa etiquetar os contatos à mão antes.

Objetivo: permitir escolher uma ou mais listas salvas como público da campanha de WhatsApp. Avaliar a extensão para SMS.

## 2. Contexto técnico *(mandatory)*

- **O público da campanha já aceita tipos.** `campaigns.audience` é `jsonb` no formato `[{ type, id }]`; `Api::V1::Accounts::CampaignsController#campaign_params` (`app/controllers/api/v1/accounts/campaigns_controller.rb:32`) permite `audience: [:type, :id]`. Hoje só existe `type: 'Label'`. Um `{ type: 'ContactFilter', id: 12 }` cabe sem migration.
- **A lista é uma consulta salva.** `CustomFilter` (`app/models/custom_filter.rb`), `filter_type: contact`, guarda `query: { payload: [...] }`. Os contatos são calculados na hora por `Contacts::FilterService` (`app/services/contacts/filter_service.rb`). Os segmentos de contato do front usam `customViews/getContactCustomViews`.
- **Há precedente de avaliar a consulta fora de requisição.** `Account::ContactsExportJob#contacts` (`app/jobs/account/contacts_export_job.rb:59-68`) chama `::Contacts::FilterService.new(@account, @account_user, @params).perform` com o `query` da lista. O `@user` do `FilterService` só é usado no caminho de conversas (`app/services/filter_service.rb:120`), não no de contatos.
- **O envio de WhatsApp já é do fork.** `Custom::Whatsapp::OneoffCampaignService` (`custom/app/services/custom/whatsapp/oneoff_campaign_service.rb`) substitui por inteiro o serviço do Enterprise (sem `super`). `create_recipients` (linha 38) faz `contacts.tagged_with(audience_labels, any: true)` e grava `ichatr_campaign_recipients` com `find_or_create_by!(contact:)`, que já deduplica. Analytics e lista de destinatários (`custom/app/controllers/api/v1/accounts/campaigns/recipients_controller.rb`) leem esses registros e não mudam.
- **`Campaign` tem ponto de extensão.** `Campaign.include_mod_with('Campaign')` (`app/models/campaign.rb:167`) → `Custom::Campaign` (`custom/app/models/custom/campaign.rb`), onde cabem validação e callbacks.
- **SMS não tem ponto de extensão.** `Sms::OneoffSmsCampaignService` e `Twilio::OneoffSmsCampaignService` repetem a lógica de etiquetas (linhas 8-20) e **não** chamam `prepend_mod_with`. Só `Whatsapp::OneoffCampaignService` chama (`app/services/whatsapp/oneoff_campaign_service.rb:153`).
- **Formulários fixam o tipo.** `WhatsAppCampaignForm.vue:63-65` monta as opções só com `labels/getLabels`; `:148-151` gera `type: 'Label'`. `SMSCampaignForm.vue:59-61` e `:96-99` fazem o mesmo. Nenhum dos dois está no MANIFEST de `bin/sync-custom-module-hooks`.
- **Listas são pessoais.** `CustomFiltersController#fetch_custom_filters`/`#fetch_custom_filter` (`app/controllers/api/v1/accounts/custom_filters_controller.rb:29-40`) filtram por `user: Current.user`.
- **Falha no disparo deixa a campanha presa.** `Campaign#trigger!` (`app/models/campaign.rb:61-67`) marca `processing` antes de executar; o enum só tem `active`, `completed` e `processing` (linha 52), e o agendador (`app/jobs/trigger_scheduled_items_job.rb:7`) só pega `active`. Uma exceção no serviço deixa a campanha em `processing` para sempre, sem envio e sem erro visível.
- **Base de contatos diferente.** `Contacts::FilterService#base_relation` (linha 32) parte de `resolved_contacts`: com `crm_v2`, só `contact_type: 'lead'`; sem ele, só contatos com email, telefone ou identifier (`app/models/contact.rb:183-186`). O caminho por etiqueta usa todos os contatos da conta.
- Campanhas de site (`Website`) não usam público (disparo por URL): fora do assunto.

## 3. Precedente *(opcional)*

- `Account::ContactsExportJob`: mesma avaliação de lista em background.
- Fase 72: substituição do serviço do Enterprise por `Custom::Whatsapp::OneoffCampaignService` e tabela de destinatários do fork.

## 4. Decisões *(mandatory)*

| # | Decisão | Justificativa |
|---|---|---|
| 1 | Novo tipo de item de público `{ type: 'ContactFilter', id }`, ao lado de `Label` | Reaproveita o formato existente; sem migration nem mudança de contrato da API |
| 2 | Ao criar ou editar a campanha, `Custom::Campaign` valida que a lista é da conta e `filter_type: contact`, e **copia o `query`** para o item (`{ type: 'ContactFilter', id, name, query }`) | Editar ou apagar a lista depois do agendamento não muda nem quebra o público. O nome copiado permite exibir o público mesmo se a lista sumir |
| 3 | Os contatos são calculados **no disparo**, a partir do `query` copiado | Mesmo comportamento das etiquetas: contatos que entrarem no filtro até o envio são incluídos |
| 4 | `create_recipients` monta o público como **união**: contatos das etiquetas ∪ contatos de cada lista | Deduplicação já existe (`find_or_create_by!(contact:)`) |
| 5 | Validar o `query` (via `FilterService`) na criação para devolver `422`, em vez de falhar só no disparo | Regra do projeto: validar na fronteira da requisição |
| 6 | Escopo inicial: **só WhatsApp** | Tudo no `custom/` exceto o formulário. SMS exige hook novo em dois serviços core |
| 7 | Combinação etiquetas + listas na mesma campanha | [A CONFIRMAR: união livre (recomendado) ou um tipo por campanha] |
| 8 | Visibilidade das listas no formulário | [A CONFIRMAR: só as listas do próprio usuário (zero mudança de modelo) ou listas compartilhadas na conta (fase própria, ver seção 6)] |
| 9 | Exceção de filtro no disparo (atributo personalizado apagado depois da criação) | [A CONFIRMAR: tratar no serviço do fork (pular a lista e registrar, ou concluir a campanha com erro visível); hoje a campanha ficaria presa em `processing`] |

## 5. Escopo preliminar *(mandatory)*

- `custom/app/services/custom/whatsapp/oneoff_campaign_service.rb`: `create_recipients` recebe etiquetas e listas; avalia cada `query` com `Contacts::FilterService` (usuário: dono da lista ou `campaign.sender`, a definir) e une com `tagged_with`.
- `custom/app/models/custom/campaign.rb`: validação da lista (decisão 2) e do `query` (decisão 5); cópia de `query`/`name` no `before_validation`.
- `app/controllers/api/v1/accounts/campaigns_controller.rb`: hoje `audience: [:type, :id]` descarta `name`/`query`; como a cópia é feita no modelo, o controller não muda. Conferir.
- `app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/WhatsAppCampaign/WhatsAppCampaignForm.vue`: seletor de listas (`customViews/getContactCustomViews`, carregar com `customViews/get` `filterType: contact`) e montagem do `audience` com os dois tipos. Arquivo upstream: edição direta com entrada no MANIFEST (`bin/sync-custom-module-hooks`), ou componente de público do fork importado no formulário (preferível: patch menor).
- Exibição do público na campanha já criada (card/analytics), se existir: conferir onde o tipo `Label` é resolvido para nome.
- i18n: `campaign.json` `en` e `pt_BR` (rótulos e placeholder do seletor de listas, erro de lista inválida); `en.yml`/`pt_BR.yml` para mensagens de validação do backend.
- SMS (se priorizado): `prepend_mod_with` em `Sms::OneoffSmsCampaignService` e `Twilio::OneoffSmsCampaignService` + MANIFEST, módulos em `custom/`, e o mesmo seletor no `SMSCampaignForm.vue`.

## 6. Fora de escopo *(mandatory)*

- **Listas compartilhadas na conta.** Exige mudar `CustomFilter`/`CustomFiltersController` (visibilidade, permissão de edição) e a UI de contatos. Fase própria, se a decisão 8 pedir.
- **Público congelado na criação** (lista de contatos fixa no momento do agendamento). Muda o comportamento em relação às etiquetas; só se houver pedido.
- Contagem prévia do público no formulário ("esta campanha vai para N contatos"). Útil, mas independente: pode reutilizar `POST /contacts/filter`.
- Campanhas de site.

## 7. Critérios de aceite (rascunho) *(mandatory)*

- No formulário de campanha de WhatsApp, é possível escolher listas de contato salvas, com ou sem etiquetas.
- Campanha com uma lista envia para todos os contatos que o filtro retorna no disparo e que têm telefone válido; os demais aparecem como `skipped`, como hoje.
- Campanha com etiqueta e lista que se sobrepõem gera um único destinatário por contato.
- Editar a lista depois de criar a campanha não muda o público da campanha; apagar a lista não impede o envio.
- Criar campanha com lista de outra conta, lista de conversa ou `query` inválido retorna `422`.
- Analytics e lista de destinatários da campanha funcionam igual para campanhas por lista.
- Campanha só com etiquetas continua igual (sem regressão).

## 8. Testes (rascunho) *(opcional)*

- `custom/spec/services/custom/whatsapp/oneoff_campaign_service_spec.rb`: lista sozinha, lista + etiqueta com sobreposição, lista que não retorna contatos.
- `custom/spec/models/custom/campaign_spec.rb` (ou request spec de campanhas): validação de conta/tipo/`query`, cópia do `query`.
- Spec JS do formulário: payload do `audience` com os dois tipos.

## 9. Questões em aberto *(opcional)*

**9.1 Usuário passado ao `FilterService`.** O serviço de contatos não usa o usuário hoje, mas a assinatura exige um. Dono da lista (`custom_filter.user`, que pode ter saído da conta) ou `campaign.sender`? [INFERÊNCIA: indiferente para o resultado atual; escolher o que não falha se o usuário for removido.]

**9.2 Diferença de base entre etiqueta e lista.** A lista parte de `resolved_contacts` (com `crm_v2`, só leads); a etiqueta não. Aceitar e documentar na UI, ou alinhar? No WhatsApp o efeito é pequeno: contato sem telefone já é pulado.

**9.3 Edição de campanha agendada.** Ao editar, recopiar o `query` da lista atual ou manter o copiado? Recomendação: recopiar só se o usuário mexer no público.

---

> **Nota de proveniência**: análise de viabilidade feita em 23/10/2026 por leitura do código do fork (4.18.0-ichatr), sem implementação nem testes. Veredito: viável para WhatsApp com risco baixo a médio, quase tudo em `custom/`; SMS viável com custo maior (hook novo em dois serviços core). Próximo passo: responder as decisões 7, 8 e 9 e seguir para brainstorm/speckit quando o Matias priorizar (`/speckit-specify`).
