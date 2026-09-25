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

    Custom::ScoutV2::RoutingSnapshot.new(
      conversation: @conversation,
      contact: contact,
      inbox: inbox,
      scout: scout,
      opportunity: opportunity,
      opportunity_stage_role: stage_role_for(scout, opportunity),
      pending_fields: compute_pending_fields(scout, opportunity),
      active_playbook: resolve_active_playbook,
      transitions: @turn_transition_count,
      satisfied_capabilities: []
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

  def compute_pending_fields(scout, opportunity)
    return [] unless opportunity

    scout_defs = scout&.required_custom_attribute_definitions || []
    stage_defs = opportunity.pipeline_stage&.required_custom_attribute_definitions || []
    all_defs = (scout_defs + stage_defs).uniq

    custom_attrs = opportunity.custom_attributes || {}
    all_defs.filter_map do |defn|
      key = defn.attribute_key
      key if custom_attrs[key].blank?
    end.uniq
  end

  def resolve_active_playbook
    state = ScoutConversationState.for_conversation(@conversation)
    return nil if state.active_playbook.blank?

    @catalog[state.active_playbook]
  end
end
