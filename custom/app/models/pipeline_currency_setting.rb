class PipelineCurrencySetting < ApplicationRecord
  self.table_name = 'matias_pipeline_currency_settings'

  belongs_to :account

  validates :currency, presence: true, inclusion: { in: %w[usd brl] }
  validates :account_id, uniqueness: true
end
