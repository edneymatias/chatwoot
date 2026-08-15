# Phase 12: Opportunity-Triggered Automations

**Status**: Ready for Planning / Implementation
**Depends on**: Phase 2 (automation integration — `create_opportunity` action), Phase 7 (stage transitions & custom fields)

## Overview

Permite que eventos do ciclo de vida das **Oportunidades** disparem regras no motor de automação do Chatwoot (`AutomationRule`). Permite alterar atributos fixos e personalizados (de Contatos, Conversas e Oportunidades), mover etapas, atribuir responsáveis e executar todas as ações existentes de conversa e integrações de forma unificada.

---

## 1. Triggers (Eventos de Gatilho)

Os seguintes eventos de oportunidade são expostos no construtor de automações:

1. **`opportunity_created`** (*Oportunidade Criada*): Disparado imediatamente após a criação de uma oportunidade.
2. **`opportunity_updated`** (*Oportunidade Atualizada*): Disparado na alteração de atributos, valores ou responsáveis.
3. **`opportunity_stage_changed`** (*Etapa Alterada*): Disparado especificamente quando a oportunidade muda de fase no pipeline.
4. **`opportunity_won`** (*Oportunidade Ganha*): Disparado quando o status muda para `won`.
5. **`opportunity_lost`** (*Oportunidade Perdida*): Disparado quando o status muda para `lost`.
6. **`opportunity_reopened`** (*Oportunidade Reaberta*): Disparado quando uma oportunidade ganha/perdida volta para `open`.

---

## 2. Conditions (Filtros e Condições)

As regras disparadas por oportunidades suportam filtros sobre:

### A. Atributos da Oportunidade
- `pipeline_id` (Pipeline pertencente)
- `pipeline_stage_id` (Etapa atual / destino)
- `from_pipeline_stage_id` (Etapa anterior / origem — relevante para `opportunity_stage_changed`)
- `status` (`open`, `won`, `lost`)
- `value` (Valor financeiro com operadores: `equal_to`, `not_equal_to`, `greater_than`, `less_than`)
- `assignee_id` (Responsável pela oportunidade)
- `loss_reason` (Motivo de perda)
- `custom_attributes` da Oportunidade (todos os campos personalizados definidos na conta)

### B. Atributos do Contato
- Nome, email, telefone, empresa, localização e `custom_attributes` do Contato.

### C. Atributos da Conversa (quando vinculada)
- Caixa de entrada (`inbox_id`), etiquetas (`labels`), prioridade, status, canal e `custom_attributes` da Conversa.

---

## 3. Actions (Ações Suportadas)

### A. Ações na Oportunidade
- `update_opportunity_stage`: Mover a oportunidade para uma etapa específica.
- `update_opportunity_assignee`: Atribuir/remover responsável pela oportunidade.
- `update_opportunity_status`: Alterar status (`open`, `won`, `lost`).
- `update_opportunity_value`: Atualizar valor financeiro.
- `update_opportunity_custom_attribute`: Definir valor de um atributo customizado da oportunidade.

### B. Ações no Contato
- `update_contact_custom_attribute`: Definir valor de um atributo customizado do contato.
- `update_contact_attribute`: Atualizar dados fixos do contato (ex: empresa, email, telefone).

### C. Ações na Conversa de Origem (com Fallback Seguro)
- Todas as ações existentes no Chatwoot:
  - `send_message` (enviar mensagem de texto)
  - `add_private_note` (adicionar nota interna)
  - `add_label` / `remove_label`
  - `assign_agent` / `assign_team` / `remove_assigned_agent` / `remove_assigned_team`
  - `resolve_conversation` / `open_conversation` / `snooze_conversation` / `pending_conversation`
  - `change_priority`
  - `send_webhook_event`
  - `send_email_to_team`
  - `update_conversation_custom_attribute`
- **Fallback Sem Conversa**: Caso a oportunidade não possua uma conversa de origem (`origin_conversation_id == nil`), as ações exclusivas de conversa são ignoradas com segurança (*no-op*), permitindo que as ações de contato e oportunidade sejam executadas sem erro.

---

## 4. Arquitetura e Prevenção de Loops

- **Listener de Eventos**: Disparos coordenados via `Custom::AutomationRuleListener` ou extensão do `AutomationRuleListener` nos callbacks do modelo `Opportunity`.
- **Prevenção de Loops**: Uso do padrão `Current.executed_by = rule` do Chatwoot para garantir que ações executadas por uma regra de automação não gerem ciclos de recursão infinita.
- **Interface UI**: 100% unificada no menu existente **Configurações > Automações** (`/app/accounts/{accountId}/settings/automation`), estendendo as constantes e componentes Vue existentes.

