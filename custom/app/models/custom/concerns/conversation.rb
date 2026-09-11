# frozen_string_literal: true

module Custom::Concerns::Conversation
  extend ActiveSupport::Concern
  included do
    has_many :opportunity_conversations,
             class_name: 'OpportunityConversation',
             dependent: :destroy
    has_many :opportunities,
             through: :opportunity_conversations
    # rubocop:disable Rails/HasManyOrHasOneDependent -- handled explicitly by
    # detach_active_opportunity below (via Opportunity#detach_active_conversation!) so the
    # deletion is logged, instead of a plain `dependent: :nullify` clearing it silently.
    has_one :active_opportunity,
            class_name: 'Opportunity',
            foreign_key: :active_conversation_id,
            inverse_of: :active_conversation
    # rubocop:enable Rails/HasManyOrHasOneDependent
    before_destroy :detach_active_opportunity

    after_commit :refresh_linked_opportunities_kanban_badges,
                 on: :update,
                 if: :saved_change_to_status_or_agent_last_seen_at?
  end

  private

  # Routed through Opportunity#detach_active_conversation! (rather than a plain
  # `dependent: :nullify`) so a conversation deletion leaves a "Conversa desanexada"
  # entry in the opportunity's history instead of silently clearing the field.
  def detach_active_opportunity
    active_opportunity&.detach_active_conversation!(reason: :deleted)
  end

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
