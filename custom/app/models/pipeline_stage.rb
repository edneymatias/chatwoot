class PipelineStage < ApplicationRecord
  self.table_name = 'matias_pipeline_stages'

  belongs_to :account
  has_many :opportunities, dependent: :restrict_with_error
  has_many :pipeline_stage_required_fields, dependent: :destroy
  has_many :required_custom_attribute_definitions, through: :pipeline_stage_required_fields, source: :custom_attribute_definition

  validates :account_id, :name, presence: true

  default_scope { order(:position) }

  before_validation :set_position, on: :create
  before_save :ensure_single_lane_exclusivity_for_deal_value, if: -> { requires_deal_value? && requires_deal_value_changed? }

  def self.seed_defaults_for!(account)
    return if account.pipeline_stages.exists?

    account.with_lock do
      next if account.pipeline_stages.exists?

      account.pipeline_stages.create!(name: 'Leads Recebidos')
      account.pipeline_stages.create!(name: 'Em Contato')
    end
  end

  private

  def set_position
    self.position ||= ((PipelineStage.where(account_id: account_id).maximum(:position) || 0) + 1) if account_id
  end

  def ensure_single_lane_exclusivity_for_deal_value
    account.pipeline_stages.where.not(id: id).update_all(requires_deal_value: false)
  end
end
