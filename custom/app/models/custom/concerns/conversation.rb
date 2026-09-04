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
  end

  private

  # Routed through Opportunity#detach_active_conversation! (rather than a plain
  # `dependent: :nullify`) so a conversation deletion leaves a "Conversa desanexada"
  # entry in the opportunity's history instead of silently clearing the field.
  def detach_active_opportunity
    active_opportunity&.detach_active_conversation!(reason: :deleted)
  end
end
