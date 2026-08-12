module Custom::Concerns::Account
  extend ActiveSupport::Concern

  included do
    has_many :pipeline_stages, dependent: :destroy
    has_many :opportunities, dependent: :destroy
    has_many :pipeline_closing_required_fields, dependent: :destroy
    has_many :pipeline_card_field_configs, dependent: :destroy
    has_one :pipeline_currency_setting, dependent: :destroy
    has_one :campaign_attribution_setting, dependent: :destroy
  end
end
