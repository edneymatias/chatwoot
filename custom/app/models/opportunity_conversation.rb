# frozen_string_literal: true

class OpportunityConversation < ApplicationRecord
  self.table_name = 'ichatr_opportunity_conversations'

  belongs_to :account
  belongs_to :opportunity, class_name: 'Opportunity'
  belongs_to :conversation, class_name: 'Conversation'

  validates :account_id, :opportunity_id, :conversation_id, presence: true
  validates :conversation_id, uniqueness: { scope: :opportunity_id }
end
