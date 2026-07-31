module Custom::Concerns::Contact
  extend ActiveSupport::Concern
  included do
    has_many :opportunities, dependent: :destroy
  end
end
