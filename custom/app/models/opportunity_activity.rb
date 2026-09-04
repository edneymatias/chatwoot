# frozen_string_literal: true

class OpportunityActivity < ApplicationRecord
  self.table_name = 'ichatr_opportunity_activities'

  belongs_to :account
  belongs_to :opportunity, class_name: 'Opportunity'
  belongs_to :actor, polymorphic: true, optional: true

  validates :account_id, :opportunity_id, :event_type, :occurred_at, presence: true

  enum event_type: {
    opportunity_created: 'opportunity_created',
    opportunity_updated: 'opportunity_updated',
    opportunity_stage_changed: 'opportunity_stage_changed',
    opportunity_won: 'opportunity_won',
    opportunity_lost: 'opportunity_lost',
    opportunity_reopened: 'opportunity_reopened',
    conversation_opened: 'conversation_opened',
    conversation_reopened: 'conversation_reopened',
    conversation_snoozed: 'conversation_snoozed',
    conversation_transferred_out: 'conversation_transferred_out',
    conversation_transferred_in: 'conversation_transferred_in',
    conversation_detached: 'conversation_detached'
  }

  def as_json(_options = {})
    {
      'id' => id,
      'event_type' => event_type,
      'metadata' => metadata,
      'occurred_at' => occurred_at.to_i,
      'actor' => actor_json
    }
  end

  private

  def actor_json
    if actor.is_a?(User)
      { 'id' => actor.id, 'type' => 'user', 'name' => actor.name }
    elsif actor.is_a?(AutomationRule)
      { 'id' => actor.id, 'type' => 'automation_rule', 'name' => actor.name }
    else
      { 'type' => 'system', 'name' => nil }
    end
  end
end
