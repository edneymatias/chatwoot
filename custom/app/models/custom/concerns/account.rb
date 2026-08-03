module Custom::Concerns::Account
  extend ActiveSupport::Concern

  included do
    has_many :pipeline_stages, dependent: :destroy
    has_many :opportunities, dependent: :destroy
    has_many :pipeline_closing_required_fields, dependent: :destroy
  end
end
