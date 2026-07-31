class Opportunity < ApplicationRecord
  self.table_name = 'matias_opportunities'

  belongs_to :account
  belongs_to :contact
  belongs_to :pipeline_stage
  belongs_to :origin_conversation, class_name: 'Conversation', optional: true
  belongs_to :assignee, class_name: 'User', optional: true

  enum status: { open: 0, won: 1, lost: 2 }

  validates :title, :contact_id, :pipeline_stage_id, :account_id, presence: true
  validate :pipeline_stage_belongs_to_account

  private

  def pipeline_stage_belongs_to_account
    return unless account_id && pipeline_stage_id

    return unless pipeline_stage&.account_id != account_id

    errors.add(:pipeline_stage, 'must belong to the same account')
  end
end
