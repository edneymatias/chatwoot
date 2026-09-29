# frozen_string_literal: true

Custom::ScoutV2::RoutingSnapshot = Data.define(
  :conversation, :contact, :inbox, :scout, :opportunity,
  :opportunity_stage_role, :pending_fields, :active_playbook,
  :transitions, :satisfied_capabilities, :completed_playbooks,
  :satisfied_business_facts
) do
  def initialize(**attrs)
    super(
      conversation: attrs[:conversation],
      contact: attrs[:contact],
      inbox: attrs[:inbox],
      scout: attrs[:scout],
      opportunity: attrs[:opportunity],
      opportunity_stage_role: attrs[:opportunity_stage_role] || :none,
      pending_fields: (attrs[:pending_fields] || []).freeze,
      active_playbook: attrs[:active_playbook],
      transitions: attrs[:transitions] || 0,
      satisfied_capabilities: (attrs[:satisfied_capabilities] || []).freeze,
      completed_playbooks: (attrs[:completed_playbooks] || []).freeze,
      satisfied_business_facts: (attrs[:satisfied_business_facts] || []).freeze
    )
  end
end
