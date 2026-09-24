# frozen_string_literal: true

class Custom::ScoutV2::Capabilities::Catalog
  KNOWN_NAMES = %w[scheduling customer_registry].freeze

  class << self
    def known?(name)
      KNOWN_NAMES.include?(name.to_s)
    end
  end
end
