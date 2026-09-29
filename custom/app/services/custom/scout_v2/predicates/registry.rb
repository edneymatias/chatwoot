# frozen_string_literal: true

class Custom::ScoutV2::Predicates::Registry
  REGISTRY = {
    'opportunity_open' => Custom::ScoutV2::Predicates::OpportunityOpen,
    'pending_required_fields' => Custom::ScoutV2::Predicates::PendingRequiredFields,
    'contact_identity_incomplete' => Custom::ScoutV2::Predicates::ContactIdentityIncomplete,
    'contact_has_phone' => Custom::ScoutV2::Predicates::ContactHasPhone,
    'in_qualification' => Custom::ScoutV2::Predicates::InQualification,
    'opportunity_in_stage' => Custom::ScoutV2::Predicates::OpportunityInStage,
    'playbook_not_completed' => Custom::ScoutV2::Predicates::PlaybookNotCompleted
  }.freeze

  ARGUMENTS = {
    'opportunity_in_stage' => :stage_role,
    'playbook_not_completed' => :playbook_name
  }.freeze

  class << self
    def registered?(name)
      REGISTRY.key?(name.to_s)
    end

    def resolve(name)
      raise ArgumentError, "Unregistered predicate: #{name.inspect}" unless registered?(name)

      REGISTRY[name.to_s]
    end

    def argument_kind(name)
      ARGUMENTS[name.to_s]
    end
  end
end
