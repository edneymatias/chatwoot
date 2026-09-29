# frozen_string_literal: true

class Custom::ScoutV2::BusinessFacts::Catalog
  KNOWN_NAMES = %w[politica_reagendamento].freeze

  class << self
    def known?(name)
      KNOWN_NAMES.include?(name.to_s)
    end
  end
end
