# frozen_string_literal: true

class Custom::ScoutV2::RoutingSnapshot::Builder
  def self.call(conversation:, catalog:, turn_transition_count: 0)
    new(
      conversation: conversation,
      catalog: catalog,
      turn_transition_count: turn_transition_count
    ).call
  end

  def initialize(conversation:, catalog:, turn_transition_count: 0)
    @conversation = conversation
    @catalog = catalog
    @turn_transition_count = turn_transition_count
  end

  def call
    contact = @conversation.contact
    inbox = @conversation.inbox
    scout = inbox&.scout
    opportunity = @conversation.active_opportunity
    state = ScoutConversationState.for_conversation(@conversation)

    Custom::ScoutV2::RoutingSnapshot.new(
      conversation: @conversation,
      contact: contact,
      inbox: inbox,
      scout: scout,
      opportunity: opportunity,
      opportunity_stage_role: stage_role_for(scout, opportunity),
      pending_fields: Custom::ScoutV2::RoutingSnapshot::PendingFields.call(scout: scout, opportunity: opportunity),
      active_playbook: resolve_active_playbook(state),
      transitions: @turn_transition_count,
      satisfied_capabilities: Custom::ScoutV2::Capabilities::Registry.satisfied_names(account: @conversation.account),
      completed_playbooks: state.completed_playbooks || [],
      satisfied_business_facts: []
    )
  end

  private

  def stage_role_for(scout, opportunity)
    return :none unless scout && opportunity&.pipeline_stage_id

    stage_id = opportunity.pipeline_stage_id
    if stage_id == scout.default_pipeline_stage_id
      :initial
    elsif stage_id == scout.qualified_stage_id
      :qualified
    elsif stage_id == scout.unqualified_stage_id
      :unqualified
    else
      :none
    end
  end

  def resolve_active_playbook(state)
    return nil if state.active_playbook.blank?

    @catalog[state.active_playbook]
  end
end
