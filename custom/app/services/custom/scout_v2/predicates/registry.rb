# frozen_string_literal: true

class Custom::ScoutV2::Predicates::Registry
  REGISTRY = {
    'opportunity_open' => Custom::ScoutV2::Predicates::OpportunityOpen,
    'pending_required_fields' => Custom::ScoutV2::Predicates::PendingRequiredFields
  }.freeze

  class << self
    def registered?(name)
      REGISTRY.key?(name.to_s)
    end

    def resolve(name)
      raise ArgumentError, "Unregistered predicate: #{name.inspect}" unless registered?(name)

      REGISTRY[name.to_s]
    end
  end
end
