# frozen_string_literal: true

module Custom::Concerns::Conversation
  extend ActiveSupport::Concern
  included do
    has_many :opportunity_conversations,
             class_name: 'OpportunityConversation',
             dependent: :destroy
    has_many :opportunities,
             through: :opportunity_conversations
    has_one :active_opportunity,
            class_name: 'Opportunity',
            foreign_key: :active_conversation_id,
            dependent: :nullify,
            inverse_of: :active_conversation

    after_commit :refresh_linked_opportunities_kanban_badges,
                 on: :update,
                 if: :saved_change_to_status_or_agent_last_seen_at?
  end

  private

  def saved_change_to_status_or_agent_last_seen_at?
    saved_change_to_status? || saved_change_to_agent_last_seen_at?
  end

  # Opportunity badges (Scout badge, unread dot) are derived from this conversation's state,
  # but nothing about this conversation change touches the Opportunity record itself, so its own
  # `after_commit :broadcast_opportunity_updated` never fires here on its own - the Kanban card
  # would keep showing (or hiding) the badge until the board is manually refreshed. Push a fresh
  # broadcast for each linked opportunity with the current (correct) badge state.
  def refresh_linked_opportunities_kanban_badges
    opportunities.find_each(&:broadcast_kanban_badges_refresh)
  end
end
