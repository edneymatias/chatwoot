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

    after_commit :refresh_linked_opportunities_scout_badge, on: :update, if: :saved_change_to_status?
  end

  private

  # Opportunity#scout_engaged? is derived from this conversation's status, but nothing about
  # this status change touches the Opportunity record itself, so its own `after_commit
  # :broadcast_opportunity_updated` never fires here on its own - the Kanban card would keep
  # showing (or hiding) the "Scout" badge until the board is manually refreshed. Push a fresh
  # broadcast for each linked opportunity with the current (correct) badge state.
  def refresh_linked_opportunities_scout_badge
    opportunities.find_each(&:broadcast_scout_badge_refresh)
  end
end
