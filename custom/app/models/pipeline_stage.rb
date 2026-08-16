class PipelineStage < ApplicationRecord
  self.table_name = 'ichatr_pipeline_stages'

  belongs_to :account
  has_many :opportunities, dependent: :restrict_with_error
  has_many :pipeline_stage_required_fields, dependent: :destroy
  has_many :required_custom_attribute_definitions, through: :pipeline_stage_required_fields, source: :custom_attribute_definition

  enum total_display_mode: { value_sum: 0, count: 1 }, _prefix: true

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

  def reorder_to!(target_position)
    PipelineStage.transaction do
      stages = account.pipeline_stages.includes(:required_custom_attribute_definitions).order(:position).lock!.to_a
      stages.delete(self)

      insert_index = [(target_position || 1).to_i - 1, stages.size].min
      insert_index = 0 if insert_index.negative?

      stages.insert(insert_index, self)

      stages.each_with_index do |stage, index|
        new_position = index + 1
        stage.update!(position: new_position) if stage.position != new_position
      end

      account.pipeline_stages.includes(:required_custom_attribute_definitions).order(:position).to_a
    end
  end

  private

  def set_position
    self.position ||= ((PipelineStage.where(account_id: account_id).maximum(:position) || 0) + 1) if account_id
  end

  def ensure_single_lane_exclusivity_for_deal_value
    account.pipeline_stages.where.not(id: id).each do |stage|
      stage.update!(requires_deal_value: false)
    end
  end
end
