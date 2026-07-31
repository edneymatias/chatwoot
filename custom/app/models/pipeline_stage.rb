class PipelineStage < ApplicationRecord
  self.table_name = 'matias_pipeline_stages'

  belongs_to :account
  has_many :opportunities, dependent: :restrict_with_error

  validates :account_id, :name, presence: true

  default_scope { order(:position) }

  before_validation :set_position, on: :create

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
end
