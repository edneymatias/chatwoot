module Custom::Concerns::Account
  extend ActiveSupport::Concern

  included do
    has_many :pipeline_stages, dependent: :destroy
    has_many :opportunities, dependent: :destroy
  end
end
