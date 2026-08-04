module Custom::Concerns::CustomAttributeDefinition
  extend ActiveSupport::Concern

  included do
    has_many :pipeline_card_field_configs, dependent: :destroy
  end
end
