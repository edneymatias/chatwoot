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
  end
end
